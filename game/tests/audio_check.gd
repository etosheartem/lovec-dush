extends SceneTree
## godot --headless --path game --script res://tests/audio_check.gd

const GameAudio = preload("res://scripts/game_audio.gd")
var failed := false
var sound
var settings_path := ""


func _initialize() -> void:
	start.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func start() -> void:
	settings_path = "user://audio_test_%s_%s.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	sound = GameAudio.new()
	sound.settings_path = settings_path
	root.add_child(sound)
	sound.set_process(false)
	check(sound.manifest.size() == 171, "Full cast manifest must load")
	check(sound.settings == {"music": 0.5, "effects": 0.7, "voice": 1.0}, "Default levels")
	var music_bus := AudioServer.get_bus_index("Music")
	var voice_bus := AudioServer.get_bus_index("Voice")
	sound.set_volume("music", 0)
	check(AudioServer.is_bus_mute(music_bus), "Zero volume must mute music")
	sound.set_volume("music", 0.35)
	sound.set_volume("effects", 0.61)
	sound.set_volume("voice", 0.73)
	check(not AudioServer.is_bus_mute(music_bus), "Raising volume must unmute music")
	check(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), linear_to_db(0.35)), "Bus follows slider")
	sound.set_volume("voice", 2, false)
	check(is_zero_approx(AudioServer.get_bus_volume_db(voice_bus)), "Volume clamps to 100%")
	sound.set_volume("voice", NAN, false)
	check(sound.settings.voice == 1, "Non-finite volume is ignored")
	sound.free()
	sound = GameAudio.new()
	sound.settings_path = settings_path
	root.add_child(sound)
	sound.set_process(false)
	check(sound.settings == {"music": 0.35, "effects": 0.61, "voice": 0.73}, "Levels survive reload")

	sound.location("3,2")
	check(sound.music.playing and sound.ambience.playing and sound.fire.playing, "Street and fire ambience starts")
	check(sound.music.stream.loop and sound.ambience.stream.loop and sound.fire.stream.loop, "Atmosphere loops")
	sound.location("1,0")
	check(sound.context == "monastery" and not sound.fire.playing, "Interior stops outdoor fire")
	sound.location("1,0", true)
	check(sound.context == "menu" and sound.music.playing, "Menu music starts")

	var lines: Array = sound.manifest.values()
	for line in lines:
		var stream: AudioStream = sound._stream("voice/" + line.file)
		check(stream != null and stream.get_length() > 0, "Every manifest recording imports: " + line.file)
	check(sound.voice_cache_order.size() == GameAudio.VOICE_CACHE_LIMIT, "Voice cache stays bounded")
	check(sound.cache.size() <= GameAudio.VOICE_CACHE_LIMIT + 6, "Played dialogue does not retain the whole cast")
	sound.say(lines[0])
	check(sound.voice.playing, "Known dialogue plays")
	sound._process(1.0)
	check(is_equal_approx(sound.music.volume_db, -10), "Speech ducks music")
	check(is_equal_approx(sound.ambience.volume_db, -5), "Speech ducks ambience")
	check(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), linear_to_db(0.35)), "Ducking preserves user volume")
	sound.set_volume("voice", 0, false)
	sound._process(1.0)
	check(is_zero_approx(sound.music.volume_db), "Muted voice must not duck music")
	sound.set_volume("voice", 0.73, false)

	await create_timer(0.12).timeout
	sound.pause_voice(true)
	check(sound.voice.stream_paused, "Pause menu pauses voice")
	await create_timer(0.12).timeout
	var paused_position: float = sound.voice.get_playback_position()
	await create_timer(0.12).timeout
	check(absf(sound.voice.get_playback_position() - paused_position) < 0.03, "Paused voice position holds")
	sound.suspend(true)
	check(sound.music.stream_paused and sound.ambience.stream_paused, "App background suspends loops")
	sound.suspend(false)
	check(sound.voice.stream_paused, "App foreground preserves menu voice pause")
	check(not sound.music.stream_paused, "App foreground resumes music")
	sound.pause_voice(false)
	check(sound.voice.playing and not sound.voice.stream_paused, "Continue resumes the same recording")
	await create_timer(0.12).timeout
	check(sound.voice.get_playback_position() > paused_position, "Resumed voice advances")
	sound.pause_voice(true)
	sound.say(lines[1])
	check(sound.voice.stream_paused, "A new line respects an existing menu pause")
	sound.effect("click")
	check(sound.effects.playing and not sound.effects.stream_paused, "Menu click stays audible during pause")
	sound.walking(0.5, true)
	check(not sound.steps.playing, "Paused game has no footsteps")
	sound.pause_voice(false)
	sound.walking(0.5, true)
	check(sound.steps.playing, "Walking plays footsteps")
	sound.walking(0.1, false)
	check(not sound.steps.playing, "Stopping movement stops footsteps")
	sound.say({"item": 1})
	check(not sound.voice.playing and sound.voice.stream == null, "Item description stops previous speech")
	sound.say({"speaker": "missing", "text": "missing"})
	check(not sound.voice.playing, "Missing optional recording stays silent")
	sound.say(lines[2])
	sound.stop_voice()
	sound._process(1.0)
	check(not sound.voice.playing and sound.voice.stream == null, "Advance stops and releases recording")
	check(is_zero_approx(sound.music.volume_db) and is_zero_approx(sound.ambience.volume_db), "End of speech restores atmosphere")
	sound.shutdown()
	check(sound.cache.is_empty() and sound.voice_cache_order.is_empty(), "Shutdown clears cached audio")
	sound.location("3,2")
	sound.say(lines[0])
	sound.walking(0.5, true)
	sound.effect("click")
	check(not sound.music.playing and not sound.voice.playing and not sound.steps.playing and not sound.effects.playing,
		"Gameplay cannot restart audio during the final quit frame")
	# AudioServer releases stopped playbacks on its following mix/update ticks.
	await create_timer(0.15).timeout
	sound.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	print("AUDIO RUNTIME OK" if not failed else "AUDIO RUNTIME FAILED")
	quit(1 if failed else 0)
