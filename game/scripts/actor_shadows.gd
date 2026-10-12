extends RefCounted
## Soft ground contact, drawn by main after the background and before actors.
## ox uses original room units; S controls sizes and KX controls world x positions.

const SceneEffects = preload("res://scripts/scene_effects.gd")
# Foot center x/y relative to the HD anchor, horizontal contact radius.
const FOOTPRINTS := {
	"devil": Vector3(4.5, 0.8, 17.0),
	"abbot": Vector3(1.0, 0.7, 23.0),
	"alchemist": Vector3(1.6, 0.6, 22.0),
	"cow": Vector3(0.0, 0.7, 33.0),
	"executioner": Vector3(2.5, 0.6, 20.0),
	"inquisitor": Vector3(-0.5, 0.7, 28.0),
	"mon": Vector3(0.7, 0.9, 19.0),
	"monk": Vector3(0.0, 0.6, 25.0),
	"objects": Vector3(0.0, 1.0, 21.0),
}

var quality := 2
var _gradient: GradientTexture2D


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)


func casts_shadow(actor, room_key: String) -> bool:
	if not FOOTPRINTS.has(actor.sheet):
		return false
	var frame: int = actor.frame()
	if actor.sheet == "objects" and (frame <= 5 or frame == 9):
		return false # Ghosts and the intentionally empty grave/novice frame.
	if actor.sheet == "mon" and room_key == "0,0" and frame >= 7 and frame <= 11:
		return false # The bell ringer is lying on the raised mattress.
	return true


func footprint(actor) -> Vector3:
	var shape: Vector3 = FOOTPRINTS.get(actor.sheet, Vector3(0, 1, 18))
	if actor.sheet == "objects":
		match int(actor.frame()):
			6:
				shape = Vector3(2.5, 0, 17)
			7, 8, 12:
				shape = Vector3(-11.5, 0.9, 20)
			10, 11:
				shape = Vector3(0.7, 0.9, 28)
	if actor.flip:
		shape.x = -shape.x
	return shape


func draw_actor_shadow(canvas: CanvasItem, actor, ox: float, lift: float,
		hdmeta: Dictionary, pixel_scale: float, kx: float, room_key: String) -> void:
	if quality == 0 or not casts_shadow(actor, room_key):
		return
	if _gradient == null:
		_create_gradient()
	var shape := footprint(actor)
	# HD foot offsets do not apply to a fallback original sprite.
	if not hdmeta.has(actor.sheet) and not hdmeta.has("canvas"):
		shape.x = 0
		shape.y = 0
	var visual_offset := Vector2.ZERO
	if canvas.has_method("_actor_visual_offset"):
		visual_offset = canvas.call("_actor_visual_offset", actor)
	var local_foot := Vector2((float(actor.x) + visual_offset.x) * kx + shape.x,
		float(actor.y) + visual_offset.y - lift + shape.y)
	var foot := (Vector2(ox * kx, 0) + local_foot) * pixel_scale
	if quality == 2:
		var lights: Array = SceneEffects.LIGHTS.get(room_key, [])
		var nearest := Vector2.ZERO
		var distance_sq := INF
		for source in lights:
			# Tiny facade lamps cannot cast a foreground actor's shadow.
			if float(source[2]) < 80:
				continue
			var light := Vector2(float(source[0]) / 1920.0 * 240.0 * kx,
				float(source[1]) / 1080.0 * 210.0)
			var separation := local_foot.distance_squared_to(light)
			if separation < distance_sq:
				distance_sq = separation
				nearest = light
		if distance_sq < INF:
			var away := local_foot - nearest
			var offset := Vector2(clampf(away.x / 9.0, -13, 13), clampf(away.y / 40.0, -2, 4))
			var radius := Vector2(shape.z + absf(offset.x) * 0.55, 5.0 + absf(offset.y) * 0.4)
			canvas.draw_set_transform(foot + offset * pixel_scale, 0, Vector2.ONE * pixel_scale)
			canvas.draw_texture_rect(_gradient, Rect2(-radius, radius * 2), false, Color(0.025, 0.023, 0.027, 0.13))
	# A compact, stable contact patch anchors feet without following animation noise.
	var contact := Vector2(shape.z, 4.2 if actor.sheet != "cow" else 5.5)
	canvas.draw_set_transform(foot, 0, Vector2.ONE * pixel_scale)
	canvas.draw_texture_rect(_gradient, Rect2(-contact, contact * 2), false, Color(0.025, 0.022, 0.026, 0.27))
	canvas.draw_set_transform(Vector2.ZERO)


func _create_gradient() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.60, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.78),
		Color(1, 1, 1, 0.26), Color(1, 1, 1, 0)])
	_gradient = GradientTexture2D.new()
	_gradient.gradient = gradient
	_gradient.width = 128
	_gradient.height = 64
	_gradient.fill = GradientTexture2D.FILL_RADIAL
	_gradient.fill_from = Vector2(0.5, 0.5)
	_gradient.fill_to = Vector2(1, 0.5)
