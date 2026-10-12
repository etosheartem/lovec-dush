extends SceneTree
## Animation clocks, movement interpolation, legacy saves and footstep cadence.

const Main = preload("res://main.gd")
const SaveStore = preload("res://scripts/save_store.gd")
var failures := 0
var checks := 0
var sprites: Dictionary


func _initialize() -> void:
	start.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL animation: ", message)


func actor(sheet: String, animation: int, next_animation := -1):
	var subject = Main.Actor.new(sheet, sprites[sheet].anims)
	subject.play(animation, next_animation, next_animation == -1)
	return subject


func clocks() -> void:
	for sheet in ["devil", "cow", "abbot", "alchemist", "mon", "monk", "inquisitor", "executioner", "objects"]:
		for animation in sprites[sheet].anims.size():
			var whole = actor(sheet, animation, 0)
			var split = actor(sheet, animation, 0)
			var elapsed := 3.14159
			whole.update(elapsed)
			var steps := [0.007, 0.016, 0.041, 0.105, 0.2]
			var index := 0
			while elapsed > 0:
				var dt := minf(elapsed, steps[index % steps.size()])
				split.update(dt)
				elapsed -= dt
				index += 1
			check(whole.anim == split.anim and whole.f == split.f and is_equal_approx(whole.t, split.t),
				"same clock under uneven rendering intervals: %s/%d" % [sheet, animation])
			check(whole.t >= 0 and whole.t < Main.FRAME, "retimed pose retains legacy save phase: %s/%d" % [sheet, animation])
	for animation in [2, 5, 6, 7, 8, 9, 10, 11, 12]:
		var subject = actor("devil", animation, 0)
		var duration: float = sprites.devil.anims[animation].size() * Main.FRAME
		subject.update(duration - 0.001)
		check(subject.anim == animation and not subject.free, "scripted action retains its full duration: %d" % animation)
		subject.update(0.002)
		check(subject.anim == 0 and subject.free and subject.t > 0, "action unlocks and preserves remaining elapsed time: %d" % animation)
	var hero = actor("devil", 0)
	hero.update(1.5)
	check(hero.frame() == 0, "neutral hero no longer blinks twice a second")
	var cow = actor("cow", 0)
	cow.update(1.0)
	check(cow.f > 0 and cow.f < sprites.cow.anims[0].size(), "cow has a deliberate chewing rhythm")
	var baseline: Array = [hero.anim, hero.f, hero.t]
	for invalid in [-1.0, 0.0, NAN, INF]:
		hero.update(invalid)
	check([hero.anim, hero.f, hero.t] == baseline, "invalid elapsed time cannot advance or hang animation")


func prepare_walk(game, start_x := 50.0, finish_x := 150.0) -> void:
	game.new_game()
	game.ev = -1
	game.dialog_lines.clear()
	game.ui_dialog.hide()
	game.sound.stop_voice()
	game.cur_key = "8,2"
	for e in game.scenes["8,2"].npcs:
		e.blocker = false
	game.devil.x = start_x
	game.devil.y = 196
	game.target = {kind = "walk", x = finish_x}
	game._fit_room_to_viewport()


func movement_and_audio() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var game = load("res://main.tscn").instantiate()
	game.persistence_enabled = false
	game.settings_path = "user://animation_check_%d.cfg" % OS.get_process_id()
	game.save_path = "user://animation_unused_%d.json" % OS.get_process_id()
	viewport.add_child(game)
	game.set_process(false)
	for width in [1920, 2400, 2520]:
		viewport.size = Vector2i(width, 1080)
		prepare_walk(game)
		for tick in 20:
			game._process(Main.TICK)
		check(is_equal_approx(game.devil.x, 50.0 + 20 * Main.STEP * Main.WALK_SPEED), "one-second traversal uses original world speed at width %d" % width)
		check(SaveStore.valid(SaveStore.capture(game), game), "new clocks still serialize to existing save format at %d" % width)
		var walk = actor("devil", 1)
		walk.update(Main.FRAME * 6 / (game.KX * Main.WALK_SPEED), game.KX * Main.WALK_SPEED)
		check(walk.f in [5, 6], "walk animation scales with on-screen speed at %d" % width)
	prepare_walk(game)
	game._process(Main.TICK)
	var logical_x: float = game.devil.x
	var first_x: float = game.devil.x + game._actor_visual_offset(game.devil).x
	game._process(Main.TICK * 0.5)
	var middle_x: float = game.devil.x + game._actor_visual_offset(game.devil).x
	check(is_equal_approx(first_x, 50.0) and is_equal_approx(middle_x, 50.0 + Main.STEP * Main.WALK_SPEED * 0.5) and game.devil.x == logical_x,
		"display interpolates between logic ticks without changing game coordinates")
	game.pause_game()
	game._process(1.0)
	check(is_equal_approx(game.devil.x + game._actor_visual_offset(game.devil).x, middle_x), "pause freezes the interpolated position")
	game.resume_game()
	game.inv = [15]
	game._on_slot(0)
	var held_pose: Array = [game.devil.x, game.devil.f, game.devil.t]
	game._process(0.3)
	check([game.devil.x, game.devil.f, game.devil.t] == held_pose, "item dialogue holds the walking pose instead of walking on the spot")
	game._advance_dialog()
	game.devil.x += 80
	check(game._actor_visual_offset(game.devil).is_zero_approx(), "teleport never interpolates across the room")
	var npc: Dictionary = game.scenes["0,2"].npcs[0]
	npc.actor.anim = -1
	npc.actor.play(0)
	npc.actor.idle_delay = 1.0
	game._npc_idle(npc)
	check(npc.actor.anim == 0, "ambient gesture waits for its rest interval")
	npc.actor.idle_delay = 0
	game._npc_idle(npc)
	check(npc.actor.anim != 0 and not npc.actor.free, "idle gesture starts from neutral and completes without interruption")
	game.sound.pause_voice(false)
	game.sound.stop_voice()
	game.sound.walking(0, false)
	game.sound.walking(0, true, 2.0)
	check(game.sound.steps.volume_db <= -9.0, "footsteps are quieter with voice absent")
	check(is_equal_approx(game.sound.step_time, 0.249), "contacts follow accelerated gait")
	var initial_variant: int = game.sound.steps.get_meta("variant")
	game.sound.walking(0.1, true, 2.0)
	check(game.sound.steps.get_meta("variant") == initial_variant, "no extra contact before its time")
	game.sound.walking(0.16, true, 2.0)
	check(game.sound.steps.get_meta("variant") != initial_variant and is_equal_approx(game.sound.step_time, 0.238),
		"next contact retains overshoot instead of drifting with frame rate")
	game.sound.pause_voice(true)
	game.sound.walking(1.0, true, 2.0)
	check(not game.sound.steps.playing, "menu pause silences even accelerated footsteps")
	game.sound.pause_voice(false)
	game.sound.walking(0, false)
	game.sound.walking(0.01, true, 1.5, 0.55)
	check(not game.sound.steps.playing, "restoring a saved mid-stride pose never invents a contact")
	game.sound.walking(0.1, true, 1.5, 0.95)
	check(not game.sound.steps.playing, "contact waits for the actual foot plant")
	game.sound.walking(0.1, true, 1.5, 1.02)
	check(game.sound.steps.playing, "crossing frame six produces the second contact")
	var phase_variant: int = game.sound.steps.get_meta("variant")
	game.sound.walking(0.1, true, 1.5, 1.95)
	check(game.sound.steps.get_meta("variant") == phase_variant, "airborne phase produces no extra contact")
	game.sound.walking(0.1, true, 1.5, 0.03)
	check(game.sound.steps.get_meta("variant") != phase_variant, "wrapped cycle produces the frame zero contact")
	game.set_process(false)
	await create_timer(0.2).timeout
	game.sound.shutdown()
	await create_timer(0.2).timeout
	game.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame


func start() -> void:
	sprites = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/sprites.json"))
	clocks()
	await movement_and_audio()
	print("ANIMATION OK: %d checks" % checks if failures == 0 else "ANIMATION FAILED: %d/%d" % [failures, checks])
	quit(1 if failures else 0)
