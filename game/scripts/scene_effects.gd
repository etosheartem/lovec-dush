extends Node2D
## Transparent ambience aligned to the painted 1920 x 1080 room backgrounds.
## world_origin is the room's top-left in world pixels, already scaled by S/KX.
## Only advance() changes animation time; menus and Android pause freeze it.

const FIRE_SHADER = preload("res://shaders/small_fire.gdshader")
const HAZE_SHADER = preload("res://shaders/scene_haze.gdshader")
const REFERENCE_SCALE := 1080.0 / 210.0
# [source x, source y, horizontal radius, vertical radius, opacity].
# Anchors measured on the actual HD pictures, not inferred from room contents.
const LIGHTS := {
	"0,0": [], "1,0": [],
	"2,0": [[536, 55, 215, 140, 0.10], [1372, 55, 215, 140, 0.10]],
	"3,0": [[1196, 96, 235, 155, 0.10]],
	"4,0": [[953, 92, 210, 140, 0.10]],
	"5,0": [[443, 92, 215, 140, 0.10], [1465, 92, 215, 140, 0.10]],
	"6,0": [], "7,0": [],
	"8,0": [[961, 33, 205, 145, 0.10], [631, 348, 140, 155, 0.09], [1243, 348, 140, 155, 0.09]],
	"9,0": [[507, 56, 215, 140, 0.10], [1415, 56, 215, 140, 0.10], [1404, 545, 120, 80, 0.065]],
	"0,1": [[493, 90, 215, 145, 0.10], [1364, 90, 215, 145, 0.10]],
	"1,1": [[969, 41, 245, 155, 0.10]],
	"2,1": [[957, 111, 195, 135, 0.10]],
	"3,1": [[611, 330, 145, 160, 0.09], [1305, 330, 145, 160, 0.09]],
	"4,1": [[443, 40, 240, 155, 0.10], [1456, 38, 240, 155, 0.10]],
	"5,1": [[929, 68, 230, 150, 0.10]],
	"6,1": [[726, 338, 145, 160, 0.09], [1226, 339, 145, 160, 0.09]],
	"7,1": [[790, 58, 200, 145, 0.10]],
	"8,1": [[506, 119, 205, 145, 0.10], [1373, 116, 205, 145, 0.10]],
	"9,1": [[514, 80, 205, 145, 0.10], [1402, 80, 205, 145, 0.10]],
	"0,2": [[403, 360, 155, 175, 0.11], [1483, 360, 155, 175, 0.11]],
	"1,2": [[805, 370, 130, 155, 0.10], [1585, 370, 130, 155, 0.10]],
	"2,2": [[493, 384, 145, 165, 0.10], [1657, 384, 145, 165, 0.10]],
	"3,2": [[1070, 386, 185, 205, 0.12], [400, 945, 165, 100, 0.10],
		[260, 672, 32, 40, 0.045], [733, 672, 32, 40, 0.045], [1395, 673, 32, 40, 0.045]],
	"4,2": [[326, 363, 160, 180, 0.11], [1614, 363, 160, 180, 0.11]],
	"5,2": [[598, 384, 130, 155, 0.10], [1487, 385, 130, 155, 0.10]],
	"6,2": [],
	"7,2": [[518, 227, 165, 185, 0.11]],
	"8,2": [[779, 347, 150, 175, 0.10], [1744, 347, 150, 175, 0.10]],
	"9,2": [[900, 200, 155, 175, 0.11]],
	"0,3": [[1146, 506, 200, 190, 0.12], [386, 689, 260, 120, 0.11],  # ад: печь, огонь под котлом,
		[850, 300, 260, 220, 0.09, Color(1.0, 0.16, 0.04)], [1580, 260, 220, 200, 0.08, Color(1.0, 0.16, 0.04)]],  # лава в трещинах
	"1,3": [[800, 211, 150, 170, 0.10], [1257, 211, 150, 170, 0.10], [1907, 200, 120, 160, 0.09],  # факелы,
		[1395, 330, 160, 260, 0.09, Color(1.0, 0.16, 0.04)]],  # лавовая жила у трона
}

var elapsed := 0.0
var quality := 2
var room_key := ""
var _lights: Array = []
var _coordinate_scale := Vector2.ONE
var _radius_scale := 1.0
var _glow: GradientTexture2D
var _fire: ColorRect
var _fire_material: ShaderMaterial
var _haze: ColorRect
var _haze_material: ShaderMaterial
var _souls := PackedVector2Array()
# Живые очаги комнат ада: [вид, x, y основания (HD 1920x1080), ширина, высота].
const SPOTS := {
	"0,3": [["fire", 300, 752, 170, 150], ["fire", 400, 760, 190, 170], ["fire", 505, 752, 170, 150],
		["fire", 1146, 584, 170, 150], ["smoke", 386, 470, 380, 360, 7.0, Color(0.80, 0.76, 0.74)]],
	"1,3": [["fire", 800, 246, 70, 110], ["fire", 1257, 246, 70, 110], ["fire", 1907, 232, 60, 100]],
}
var _spots: Array = []         # [ColorRect, ShaderMaterial, описание]


func configure(key: String, world_origin: Vector2, pixel_scale: float, kx: float) -> void:
	if _glow == null:
		_create_resources()
	if room_key != key:
		_souls.clear()
	room_key = key
	position = world_origin
	_coordinate_scale = Vector2(240.0 * kx / 1920.0, 210.0 / 1080.0) * pixel_scale
	_radius_scale = pixel_scale / REFERENCE_SCALE
	_lights = LIGHTS.get(key, [])
	_fire.position = Vector2(400, 970) * _coordinate_scale + Vector2(-105, -180) * _radius_scale
	_fire.size = Vector2(210, 180) * _radius_scale
	_fire_material.set_shader_parameter("phase", elapsed)
	_place_spots()
	_update_quality()
	queue_redraw()


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	if _glow != null:
		_update_quality()
	queue_redraw()


func set_souls(world_centers: PackedVector2Array) -> void:
	_souls = world_centers.duplicate()
	queue_redraw()


func _place_spots() -> void:
	var wanted: Array = SPOTS.get(room_key, [])
	for i in _spots.size():
		var rect: ColorRect = _spots[i][0]
		var mat: ShaderMaterial = _spots[i][1]
		if i >= wanted.size():
			rect.visible = false
			continue
		var d: Array = wanted[i]
		_spots[i][2] = d
		mat.shader = FIRE_SHADER if d[0] == "fire" else HAZE_SHADER
		if d[0] == "smoke":
			mat.set_shader_parameter("smoke", true)
			mat.set_shader_parameter("strength", d[5] if d.size() > 5 else 1.0)
			var tint: Color = d[6] if d.size() > 6 else Color(0.33, 0.32, 0.30)
			mat.set_shader_parameter("smoke_tint", Vector3(tint.r, tint.g, tint.b))
		mat.set_shader_parameter("phase", elapsed + float(i) * 3.7)  # очаги не в такт
		rect.position = Vector2(d[1], d[2]) * _coordinate_scale + Vector2(-d[3] * 0.5, -d[4]) * _radius_scale
		rect.size = Vector2(d[3], d[4]) * _radius_scale


func _update_quality() -> void:
	for spot in _spots:
		var d: Array = spot[2]
		spot[0].visible = not d.is_empty() and SPOTS.get(room_key, []).has(d) \
			and (quality > 0 if d[0] == "fire" else quality == 2)
	_fire.visible = quality > 0 and room_key == "3,2"
	_haze.visible = quality == 2 and room_key in ["3,2", "6,2", "7,2", "8,2"]
	var smoke := room_key == "3,2"
	_haze_material.set_shader_parameter("smoke", smoke)
	_haze_material.set_shader_parameter("phase", elapsed)
	if smoke:
		_haze.position = Vector2(400, 970) * _coordinate_scale + Vector2(-145, -330) * _radius_scale
		_haze.size = Vector2(290, 330) * _radius_scale
	else:
		_haze.position = Vector2(0, 790) * _coordinate_scale
		_haze.size = Vector2(1920, 290) * _coordinate_scale


func advance(dt: float) -> void:
	if dt <= 0 or not is_finite(dt) or quality == 0:
		return
	elapsed += dt
	if _fire_material != null and _fire.visible:
		_fire_material.set_shader_parameter("phase", elapsed)
	if _haze_material != null and _haze.visible:
		_haze_material.set_shader_parameter("phase", elapsed)
	for i in _spots.size():
		if _spots[i][0].visible:
			_spots[i][1].set_shader_parameter("phase", elapsed + float(i) * 3.7)
	if not _lights.is_empty() or not _souls.is_empty():
		queue_redraw()


func _create_resources() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.40, 0.70, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.72),
		Color(1, 1, 1, 0.30), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.width = 128
	_glow.height = 128
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_fire_material = ShaderMaterial.new()
	_fire_material.shader = FIRE_SHADER
	_fire = ColorRect.new()
	_fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fire.material = _fire_material
	_fire.visible = false
	add_child(_fire)
	_haze_material = ShaderMaterial.new()
	_haze_material.shader = HAZE_SHADER
	_haze = ColorRect.new()
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_haze.material = _haze_material
	_haze.visible = false
	add_child(_haze)
	var most := 0
	for key in SPOTS:
		most = maxi(most, SPOTS[key].size())
	for i in most:  # пул на всю игру: смена комнаты не создаёт узлов
		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.visible = false
		var mat := ShaderMaterial.new()
		rect.material = mat
		add_child(rect)
		_spots.append([rect, mat, []])


func _draw() -> void:
	if _glow == null or quality == 0:
		return
	for i in _lights.size():
		var light: Array = _lights[i]
		var center := Vector2(light[0], light[1]) * _coordinate_scale
		var radius := Vector2(light[2], light[3]) * _radius_scale
		var seed := float(i) * 1.71 + float(room_key.hash() % 31)
		# Small, independent, continuous fluctuations; never random frame flashes.
		var flicker := 1.0 + 0.042 * sin(elapsed * 0.91 + seed) \
			+ 0.023 * sin(elapsed * 1.71 + seed * 2.3) + 0.012 * sin(elapsed * 2.63 + seed)
		var tint := Color(1.0, 0.54, 0.17, float(light[4]) * flicker)
		if (room_key == "3,2" and i == 1) or (room_key == "9,0" and i == 2):
			tint = Color(1.0, 0.28, 0.055, tint.a)
		if light.size() > 5:  # свой цвет; лава дышит медленно и глубже
			var lava := 1.0 + 0.35 * sin(elapsed * 0.6 + seed)
			tint = Color(light[5].r, light[5].g, light[5].b, float(light[4]) * lava)
		draw_texture_rect(_glow, Rect2(center - radius, radius * 2.0), false, tint)
		if quality == 2 and room_key.get_slice(",", 1) != "2":
			_draw_motes(center, radius.x, seed)
	for i in _souls.size():
		var center := _souls[i] - position
		var radius := Vector2(85, 110) * _radius_scale
		var pulse := 0.96 + 0.04 * sin(elapsed * 1.2 + float(i) * 2.1)
		draw_texture_rect(_glow, Rect2(center - radius, radius * 2.0), false, Color(0.24, 0.60, 0.90, 0.065 * pulse))
		if quality == 2:
			for mote in 3:
				var angle := elapsed * 0.22 + float(mote) * TAU / 3.0 + float(i)
				var offset := Vector2(cos(angle) * 54, sin(angle) * 82) * _radius_scale
				draw_circle(center + offset, 1.15 * _radius_scale, Color(0.43, 0.77, 0.96, 0.20), true, -1.0, true)


func _draw_motes(center: Vector2, radius: float, seed: float) -> void:
	# Four deterministic specks in each pool of light, fading in/out over ~16s.
	for i in 4:
		var index := float(i)
		var life := fposmod(elapsed * (0.054 + index * 0.004) + index * 0.237 + seed * 0.131, 1.0)
		var opacity := sin(life * PI) * sin(life * PI) * 0.19
		var offset := Vector2(sin(index * 2.41 + seed) * radius * 0.45
			+ sin(elapsed * 0.17 + index) * 14 * _radius_scale,
			(38 + life * 175) * _radius_scale)
		draw_circle(center + offset, (0.8 + index * 0.13) * _radius_scale,
			Color(0.95, 0.72, 0.37, opacity), true, -1.0, true)
