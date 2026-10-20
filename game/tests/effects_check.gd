extends SceneTree
## Headless contracts, plus actual pixels when a rendering display is available.
## godot --headless --path game --script res://tests/effects_check.gd
## godot --path game --rendering-method mobile --script res://tests/effects_check.gd -- --screenshots=/tmp/lovec_fx

const SceneEffects = preload("res://scripts/scene_effects.gd")
const ActorShadows = preload("res://scripts/actor_shadows.gd")
const SCALE := 1080.0 / 210.0
const KX := 1920.0 / (240.0 * SCALE)
var checks := 0
var failures := 0
var screenshots := ""


class Subject:
	var sheet := "devil"
	var x := 115.0
	var y := 196.0
	var flip := false
	var current_frame := 0
	func frame() -> int:
		return current_frame


class ShadowCanvas extends Node2D:
	var shadows = ActorShadows.new()
	var subject = Subject.new()
	var background: Texture2D
	var actor_texture: Texture2D
	var hdmeta := {}
	var key := "3,2"
	var draw_actor := true
	func _draw() -> void:
		draw_texture_rect(background, Rect2(0, 0, 1920, 1080), false)
		shadows.draw_actor_shadow(self, subject, 0, 0, hdmeta, SCALE, KX, key)
		if draw_actor:
			var meta: Dictionary = hdmeta[subject.sheet]
			draw_set_transform(Vector2(subject.x * KX, subject.y) * SCALE, 0, Vector2.ONE * SCALE)
			draw_texture_rect(actor_texture, Rect2(-meta.anchor[0], -meta.anchor[1], meta.canvas[0], meta.canvas[1]), false)


func _initialize() -> void:
	start.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL effects: ", message)


func start() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshots="):
			screenshots = argument.trim_prefix("--screenshots=")
	if not screenshots.is_empty():
		DirAccess.make_dir_recursive_absolute(screenshots)
	check_contracts()
	if DisplayServer.get_name() != "headless":
		await check_pixels()
	else:
		print("EFFECTS: pixel checks skipped in headless mode")
	print("EFFECTS OK: %d checks" % checks if failures == 0 else "EFFECTS FAILED: %d/%d" % [failures, checks])
	quit(1 if failures else 0)


func check_contracts() -> void:
	var fx = SceneEffects.new()
	root.add_child(fx)
	for key in SceneEffects.LIGHTS:
		fx.configure(key, Vector2.ZERO, SCALE, KX)
		check(fx.get_child_count() == 2 + fx._spots.size(), "room switch reuses fire, haze and spot nodes: " + key)
		for level in 3:
			fx.set_quality(level)
			check(fx._fire.visible == (level > 0 and key == "3,2"), "fire profile: %s/%d" % [key, level])
			check(fx._haze.visible == (level == 2 and key in ["3,2", "6,2", "7,2", "8,2"]), "haze profile: %s/%d" % [key, level])
	fx.configure("3,2", Vector2(170, 60), SCALE, KX)
	fx.set_quality(2)
	fx.advance(0.75)
	check(is_equal_approx(fx.elapsed, 0.75), "explicit time advances")
	check(fx._fire_material.get_shader_parameter("phase") == fx.elapsed
		and fx._haze_material.get_shader_parameter("phase") == fx.elapsed, "all shaders use explicit game time")
	fx.advance(0)
	fx.advance(-1)
	fx.advance(NAN)
	check(is_equal_approx(fx.elapsed, 0.75), "zero, negative and invalid time cannot animate")
	fx.set_quality(0)
	fx.advance(12)
	check(is_equal_approx(fx.elapsed, 0.75), "disabled effects do no animation work")
	fx.set_souls(PackedVector2Array([Vector2(200, 300)]))
	fx.configure("3,2", Vector2(170, 60), SCALE * 0.5, KX * 1.25)
	check(fx.position == Vector2(170, 60), "world origin remains a world-pixel translation")
	check(fx._fire.size.is_equal_approx(Vector2(105, 90)), "fire scales with world pixel scale")
	check((fx._fire.position + Vector2(52.5, 90)).is_equal_approx(Vector2(250, 485)), "anchor scales x with KX and y with S")
	check(fx._souls.size() == 1, "resize preserves existing souls")
	fx.configure("6,2", Vector2.ZERO, SCALE, KX)
	check(fx._souls.is_empty(), "new room cannot retain old soul halos")
	check(fx._haze.size.is_equal_approx(Vector2(1920, 290)), "fog uses the full room width after resize")
	fx.free()
	var shadows = ActorShadows.new()
	var actor = Subject.new()
	actor.sheet = "objects"
	for frame in 6:
		actor.current_frame = frame
		check(not shadows.casts_shadow(actor, "0,1"), "ghost never casts a physical contact shadow")
	actor.current_frame = 9
	check(not shadows.casts_shadow(actor, "9,1"), "empty object never casts a shadow")
	for frame in [6, 7, 8, 10, 11, 12]:
		actor.current_frame = frame
		check(shadows.casts_shadow(actor, "9,1"), "physical object casts shadow: %d" % frame)
	actor.current_frame = 7
	var robot_contact: Vector3 = shadows.footprint(actor)
	actor.current_frame = 12
	check(shadows.footprint(actor) == robot_contact, "robot contact remains stable when the vase breaks")
	actor.sheet = "mon"
	actor.current_frame = 7
	check(not shadows.casts_shadow(actor, "0,0"), "sleeping bell ringer has no floor shadow below mattress")
	check(shadows.casts_shadow(actor, "7,2"), "lying on actual ground can still cast a shadow")
	actor.sheet = "devil"
	var normal: Vector3 = shadows.footprint(actor)
	actor.flip = true
	var flipped: Vector3 = shadows.footprint(actor)
	check(normal.x == -flipped.x and normal.y == flipped.y and normal.z == flipped.z, "flipped feet preserve the ground plane")


func capture(viewport: SubViewport, name: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	if not screenshots.is_empty() and not name.is_empty():
		picture.save_png(screenshots.path_join(name + ".png"))
	return picture


func check_pixels() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas = ShadowCanvas.new()
	canvas.hdmeta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/hd/hd.json"))
	canvas.actor_texture = load("res://assets/hd/devil/0.png")
	canvas.background = load("res://assets/hd/scenes/3_2.png")
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	viewport.add_child(canvas)
	var fx = SceneEffects.new()
	viewport.add_child(fx)
	for key in ["3,2", "8,0", "7,2"]:
		canvas.key = key
		canvas.background = load("res://assets/hd/scenes/%s.png" % key.replace(",", "_"))
		canvas.queue_redraw()
		fx.configure(key, Vector2.ZERO, SCALE, KX)
		var profiles := []
		for level in 3:
			canvas.shadows.set_quality(level)
			canvas.queue_redraw()
			fx.set_quality(level)
			profiles.append(await capture(viewport, "%s_quality_%d" % [key.replace(",", "_"), level]))
		check(profiles[0].get_data() != profiles[1].get_data(), "contact shadows/light make quality 1 visibly different: " + key)
		check(profiles[1].get_data() != profiles[2].get_data(), "haze/motes make quality 2 visibly different: " + key)
		var detail_region: Rect2i = {
			"3,2": Rect2i(320, 710, 180, 110),
			"7,2": Rect2i(100, 865, 450, 150),
			"8,0": Rect2i(475, 375, 310, 225),
		}[key]
		check(profiles[1].get_region(detail_region).get_data() != profiles[2].get_region(detail_region).get_data(),
			"smoke, ground mist or motes render independently of actor shadows: " + key)
		var paused: Image = profiles[2]
		await create_timer(0.16).timeout
		var held := await capture(viewport, "")
		check(paused.get_data() == held.get_data(), "pause freezes every visible pixel: " + key)
		fx.advance(1.1)
		var moved := await capture(viewport, key.replace(",", "_") + "_advanced")
		check(paused.get_data() != moved.get_data(), "explicit advance moves the visible effects: " + key)
		# No full-screen overlay or accidental opaque ColorRect corner.
		check(profiles[0].get_pixel(15, 500) == profiles[2].get_pixel(15, 500), "unlit background outside effect bounds stays untouched: " + key)
	viewport.size = Vector2i(960, 540)
	canvas.scale = Vector2(0.5, 0.5)
	fx.configure("7,2", Vector2.ZERO, SCALE * 0.5, KX)
	var resized := await capture(viewport, "7_2_half_size")
	check(resized.get_size() == Vector2i(960, 540), "resized effects render in the new viewport")
	var held_size := await capture(viewport, "")
	check(resized.get_data() == held_size.get_data(), "resize preserves paused image without phase jumps")
	fx.set_quality(1)
	var resized_high := await capture(viewport, "")
	check(resized.get_region(Rect2i(50, 433, 225, 75)).get_data() != resized_high.get_region(Rect2i(50, 433, 225, 75)).get_data(),
		"ground mist scales with the scene and remains optional after resize")
	viewport.size = Vector2i(1920, 1080)
	canvas.scale = Vector2.ONE
	fx.set_quality(2)
	fx.configure("0,0", Vector2.ZERO, SCALE, KX)
	canvas.shadows.set_quality(0)
	canvas.draw_actor = false
	canvas.queue_redraw()
	var empty := await capture(viewport, "")
	fx.set_souls(PackedVector2Array([Vector2(900, 650)]))
	var souls := await capture(viewport, "soul_halo")
	check(empty.get_data() != souls.get_data(), "soul hook draws a visible local halo")
	fx.set_quality(0)
	var off := await capture(viewport, "")
	check(empty.get_data() == off.get_data(), "economy disables soul halos as well as all other effects")
	viewport.queue_free()
	await process_frame
