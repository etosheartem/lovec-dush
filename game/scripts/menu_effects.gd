extends Control
## Decorative home layer: explicit time, deterministic dust, no input or scene processing.
## Candle coordinates refer to the original 1536 x 864 art and follow aspect-cover cropping.

const ART_SIZE := Vector2(1536, 864)
const CANDLES := [Vector2(77, 364), Vector2(128, 325), Vector2(180, 365),
	Vector2(1355, 366), Vector2(1404, 325), Vector2(1455, 365)]
const DUST_COUNT := 12

var quality := 2
var elapsed := 0.0
var _glow: GradientTexture2D
var _hero: TextureRect
var _hero_offsets := Vector4.ZERO
var _hero_modulate := Color.WHITE


func _ready() -> void:
	name = "MenuEffects"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = blend
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.18, 0.46, 0.74, 1])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.74),
		Color(1, 1, 1, 0.28), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0)])
	_glow = GradientTexture2D.new()
	_glow.width = 128
	_glow.height = 128
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1, 0.5)
	_glow.gradient = gradient
	resized.connect(queue_redraw)
	set_process(false)


func configure(level: int, hero: TextureRect = null) -> void:
	restore_hero()
	quality = clampi(level, 0, 2)
	_hero = hero
	if is_instance_valid(_hero):
		_hero_offsets = Vector4(_hero.offset_left, _hero.offset_top, _hero.offset_right, _hero.offset_bottom)
		_hero_modulate = _hero.modulate
	visible = quality > 0
	queue_redraw()


func advance(dt: float) -> void:
	if quality == 0 or not is_finite(dt) or dt <= 0:
		return
	elapsed += dt
	if quality == 2 and is_instance_valid(_hero):
		# A rigid subpixel shift preserves the painted anatomy and grounded composition.
		var scale_factor := size.y / ART_SIZE.y
		var shift := Vector2(sin(elapsed * 0.47) * 0.8, sin(elapsed * 0.63) * 0.32) * scale_factor
		_hero.offset_left = _hero_offsets.x + shift.x
		_hero.offset_top = _hero_offsets.y + shift.y
		_hero.offset_right = _hero_offsets.z + shift.x
		_hero.offset_bottom = _hero_offsets.w + shift.y
		var warmth := 0.997 + sin(elapsed * 0.71) * 0.003
		_hero.modulate = _hero_modulate * Color(1, warmth, warmth * 0.999, 1)
	queue_redraw()


func restore_hero() -> void:
	if is_instance_valid(_hero):
		_hero.offset_left = _hero_offsets.x
		_hero.offset_top = _hero_offsets.y
		_hero.offset_right = _hero_offsets.z
		_hero.offset_bottom = _hero_offsets.w
		_hero.modulate = _hero_modulate
	_hero = null


func _exit_tree() -> void:
	restore_hero()


func art_point(point: Vector2) -> Vector2:
	var cover_scale := maxf(size.x / ART_SIZE.x, size.y / ART_SIZE.y)
	return (size - ART_SIZE * cover_scale) * 0.5 + point * cover_scale


func _draw() -> void:
	if quality == 0 or _glow == null:
		return
	var cover_scale := maxf(size.x / ART_SIZE.x, size.y / ART_SIZE.y)
	for index in CANDLES.size():
		var center := art_point(CANDLES[index])
		# Slow, overlapping waves instead of random flicker or strobing.
		var breath := sin(elapsed * 1.37 + index * 1.73) * 0.10 + sin(elapsed * 2.19 + index) * 0.045
		var radius := 53.0 * cover_scale * (1.0 + breath * 0.08)
		draw_texture_rect(_glow, Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2),
			false, Color(1.0, 0.57, 0.22, 0.083 * (1.0 + breath)))
		var flame_size := Vector2(4.0, 8.0 + breath * 3.0) * cover_scale
		draw_texture_rect(_glow, Rect2(center - flame_size * 0.5, flame_size),
			false, Color(1.0, 0.77, 0.38, 0.22 * (1.0 + breath)))
	if quality < 2:
		return
	for index in DUST_COUNT:
		# Fixed paths need no RNG, emitter nodes, physics, or per-frame allocation.
		var seed_phase := float(index) * 2.399963
		var travel := fposmod(float(index) / DUST_COUNT + elapsed / (31.0 + index * 1.3), 1.0)
		var point := Vector2(90 + fposmod(index * 83.0, 535.0), 710.0 - travel * 465.0)
		point.x += sin(elapsed * 0.16 + seed_phase) * 14.0
		var fade := sin(travel * PI) * (0.64 + 0.36 * sin(elapsed * 0.43 + seed_phase))
		var radius := (1.1 + float(index % 3) * 0.28) * cover_scale
		draw_texture_rect(_glow, Rect2(art_point(point) - Vector2.ONE * radius, Vector2.ONE * radius * 2),
			false, Color(1.0, 0.75, 0.42, 0.19 * fade))
