extends Node
## Offline music, ambience, Foley and recorded dialogue. No network or API keys.

const BASE := "res://assets/audio/"
const VOICE_CACHE_LIMIT := 8
const STEP_LEVEL_DB := -9.0
const BUSES := {"music": "Music", "effects": "Effects", "voice": "Voice"}
var settings := {"music": 0.5, "effects": 0.7, "voice": 1.0}
var settings_path := "user://settings.cfg"
var music: AudioStreamPlayer
var ambience: AudioStreamPlayer
var fire: AudioStreamPlayer
var voice: AudioStreamPlayer
var effects: AudioStreamPlayer
var steps: AudioStreamPlayer
var manifest := {}
var cache := {}
var voice_cache_order: Array[String] = []
var context := ""
var step_time := 0.0
var last_gait_phase := -1.0
var suspended := false
var dialogue_paused := false
var shutting_down := false


func _ready() -> void:
	for channel in ["Music", "Effects", "Voice"]:
		if AudioServer.get_bus_index(channel) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, channel)
	music = _player("Music")
	ambience = _player("Effects")
	fire = _player("Effects")
	voice = _player("Voice")
	voice.finished.connect(_release_voice)
	effects = _player("Effects")
	effects.max_polyphony = 4
	steps = _player("Effects")
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		for key in settings:
			var value = cfg.get_value("audio", key, settings[key])
			if (value is float or value is int) and is_finite(value):
				settings[key] = clampf(value, 0, 1)
	for key in settings:
		set_volume(key, settings[key], false)
	var path := BASE + "voice/manifest.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			manifest = parsed


func _player(bus_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus_name
	add_child(player)
	return player


func set_volume(key: String, value: float, persist := true) -> void:
	if not BUSES.has(key) or not is_finite(value):
		return
	value = clampf(value, 0, 1)
	settings[key] = clampf(value, 0, 1)
	var bus_name: String = BUSES[key]
	var index := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
	AudioServer.set_bus_mute(index, value <= 0)
	if persist:
		var cfg := ConfigFile.new()
		cfg.load(settings_path) # Preserve independent debug options in the same profile.
		for setting in settings:
			cfg.set_value("audio", setting, settings[setting])
		cfg.save(settings_path)


func _stream(name: String) -> AudioStream:
	if not cache.has(name) and ResourceLoader.exists(BASE + name):
		cache[name] = load(BASE + name)
	if name.begins_with("voice/") and cache.has(name):
		# Keep only recent compressed recordings, not the entire cast on mobile.
		voice_cache_order.erase(name)
		voice_cache_order.append(name)
		while voice_cache_order.size() > VOICE_CACHE_LIMIT:
			cache.erase(voice_cache_order.pop_front())
	return cache.get(name)


func _loop(player: AudioStreamPlayer, name: String) -> void:
	var stream := _stream(name + ".ogg")
	if stream == null:
		return
	stream.loop = true
	player.stream = stream
	player.play()
	player.stream_paused = suspended


func location(room: String, in_menu := false) -> void:
	if shutting_down:
		return
	if in_menu:
		walking(0, false) # A later Continue must initialize contacts from its saved gait.
	var outside := room.get_slice(",", 1) == "2"
	var next_context := "menu" if in_menu else "street" if outside else "monastery"
	if context != next_context:
		context = next_context
		_loop(music, "music_" + context)
		_loop(ambience, "ambient_street" if outside else "ambient_monastery")
	if not in_menu and (room == "3,2" or room.ends_with(",3")):  # костёр и пекло ада
		if not fire.playing:
			_loop(fire, "ambient_fire")
	else:
		fire.stop()


func effect(name: String) -> void:
	if suspended or shutting_down:
		return
	var stream := _stream(name + ".wav")
	if stream:
		effects.stream = stream
		effects.play()


func walking(dt: float, moving: bool, playback_rate := 1.0, gait_phase := -1.0) -> void:
	if not moving or suspended or dialogue_paused or shutting_down:
		step_time = 0
		last_gait_phase = -1
		steps.stop()
		return
	var interval := 0.498 / maxf(playback_rate, 0.1)
	var contact := false
	var tracked_phase := gait_phase >= 0 and is_finite(gait_phase)
	if tracked_phase:
		# The saved animation phase is authoritative, including after pause/reload.
		var phase := fposmod(gait_phase, 2.0)
		contact = is_zero_approx(fposmod(phase, 1.0)) if last_gait_phase < 0 \
			else floori(phase) != floori(last_gait_phase) or phase < last_gait_phase
		last_gait_phase = phase
		step_time = (1.0 - fposmod(phase, 1.0)) * interval
	else:
		# Standalone callers without an actor still get two contacts per walk cycle.
		step_time -= dt
		contact = step_time <= 0
	if contact:
		if not tracked_phase:
			step_time += interval
			if step_time <= 0:
				step_time = interval # Avoid a burst of stale contacts after a stalled frame.
		var previous: int = steps.get_meta("variant", -1)
		var variant := randi() % 4 if previous < 0 else (previous + 1 + randi() % 3) % 4
		steps.set_meta("variant", variant)
		steps.stream = _stream("step_%d.wav" % variant)
		steps.volume_db = STEP_LEVEL_DB - (6.0 if voice.playing and not voice.stream_paused and settings.voice > 0 else 0.0)
		if steps.stream:
			steps.play()


func say(line: Dictionary) -> void:
	stop_voice()
	if shutting_down or not line.has("text") or not line.has("speaker"):
		return
	var key: String = (str(line.speaker) + "\n" + str(line.text)).sha256_text()
	if manifest.has(key):
		voice.stream = _stream("voice/" + manifest[key].file)
		if voice.stream:
			voice.play()
			voice.stream_paused = suspended or dialogue_paused


func stop_voice() -> void:
	voice.stop()
	_release_voice()


func _release_voice() -> void:
	voice.stream = null


func pause_voice(paused: bool) -> void:
	dialogue_paused = paused
	voice.stream_paused = suspended or dialogue_paused
	steps.stop()
	# Short Foley must not spill into the pause menu; menu clicks stay available.
	if paused:
		effects.stop()


func suspend(paused: bool) -> void:
	suspended = paused
	for player in [music, ambience, fire, voice, effects, steps]:
		player.stream_paused = paused
	voice.stream_paused = suspended or dialogue_paused
	if paused:
		steps.stop()


func shutdown() -> void:
	shutting_down = true
	set_process(false)
	for player in [music, ambience, fire, voice, effects, steps]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	cache.clear()
	voice_cache_order.clear()
	context = ""


func _exit_tree() -> void:
	shutdown()


func _process(dt: float) -> void:
	# Leave space for speech without changing the user's volume setting.
	var speaking: bool = voice.playing and not voice.stream_paused and settings.voice > 0
	var target_db := -10.0 if speaking else 0.0
	music.volume_db = move_toward(music.volume_db, target_db, dt * 22)
	ambience.volume_db = move_toward(ambience.volume_db, target_db * 0.5, dt * 15)
