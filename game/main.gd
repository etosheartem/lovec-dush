extends Node2D
## «Ловец душ» — порт логики J2ME-оригинала (Dynamic Pixels, 2007).
## Мир живёт в координатах оригинала (сцена 240x210), на экран — с масштабом S.
## Альбом: как в оригинале — на экране одна комната по центру, переходы с затемнкой.
## Широкие HD-фоны: по X всё рисуется с множителем KX (логика остаётся в координатах оригинала).
## Данные: assets/game.json (original/extract.py), спрайты: assets/sprites (original/export_sprites.py).

const S := 1080.0 / 210.0     # сцена во всю высоту экрана
const ROOM_W := 240
const TICK := 0.05            # игровой тик оригинала (Midlet: 50 мс)
const FRAME := 0.083          # кадр анимации (d.a(): 83 мс)
const STEP := 4               # шаг чёрта за тик (k.b)
const WALK_SPEED := 0.7       # ходьба медленнее оригинала на 30%; анимация и шаги в такт
const INV_CAP := 2            # k.c = new t(2)
const FIDGETS := [0, 4, 4, 4, 4, 5, 4, 4, 6, 4, 4, 7]  # v.u: случайные ужимки после 5 с простоя
# «Глазки»-подсказки (лист virtual, v.v): 0 — открыт, 1 — моргнул, 2 — пусто.
const EYE_ANIMS := [[2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2]]
const EYE_SHIFT := {"6,2/0": Vector2(-14, 17), "8,2/0": Vector2(0, 17)}  # в HD кресты ниже/левее оригинала
const SCENE_H := 210
const SaveStore = preload("res://scripts/save_store.gd")
const GameAudio = preload("res://scripts/game_audio.gd")
const GameMenu = preload("res://scripts/game_menu.gd")
const SceneEffects = preload("res://scripts/scene_effects.gd")
const GraphicsSettings = preload("res://scripts/graphics_settings.gd")
const ActorShadows = preload("res://scripts/actor_shadows.gd")
const AnimationTiming = preload("res://scripts/animation_timing.gd")
const Stats = preload("res://scripts/stats.gd")

var save_path := "user://progress.json"
var settings_path := "user://settings.cfg"
var persistence_enabled := true
var in_game := false
var menu_open := true
var save_pending := false
var autosave_time := 0.0
var drop_slot := -1
var sound
var menus
var scene_effects
var graphics
var actor_shadows = ActorShadows.new()
var background_cache_path := ""
var game_layer: CanvasLayer
var drop_buttons: Array = []
var hud_status: Label
var status_time := 0.0
var quitting := false

var G: Dictionary
var SPR: Dictionary
var tex_cache := {}
var scenes := {}
var cur_key := "3,2"
var inv: Array = []
var souls := {}
var burn_msg := 44            # u.a: реплики 44..46 по кругу
var ev := -1                  # очередь скриптов — один слот, как u.b
var ev_wait := 0
var saved := []               # u.d/e/f: поза палача до броска
var pending_pick := -2        # -2 нет, -1 бросить, >=0 индекс предмета на полу
var target := {}              # куда идём и что сделать по приходу
var idle_time := 0.0
var tick_acc := 0.0
var ended := false
var devil: Actor
var hd := {}                  # assets/hd/hd.json: перерисованные листы (холст и якорь в единицах оригинала)
var _eye_tex: Texture2D = preload("res://assets/sprites/virtual.png")  # 8× оригинала, nearest
var KX := 1.0                 # ширина комнаты под текущий экран, без растяжения персонажей
var cam: Camera2D
var fade: ColorRect
var follow_x := -1.0          # куда идти после перехода (тап в соседнюю комнату)
var walk_previous := Vector2(NAN, NAN)
var walk_room := ""

var dialog_lines: Array = []
var ui_dialog: Panel
var ui_avatar: TextureRect
var ui_name: Label
var ui_text: Label
var ui_slots: Array = []
var stats: Stats


class Actor:
	var sheet: String
	var anims: Array
	var x := 0.0
	var y := 0.0
	var flip := false
	var anim := -1
	var next := -1
	var free := true          # d.y: false — анимация залочена, управление/скрипты ждут
	var f := 0
	var t := 0.0
	var idle_delay := 3.0

	func _init(sheet_: String, anims_: Array) -> void:
		sheet = sheet_
		anims = anims_
		idle_delay = randf_range(3.0, 6.0)

	func play(a: int, nxt := -1, free_ := true) -> void:
		if a == anim:
			return
		anim = a
		next = nxt
		free = free_
		f = 0
		t = 0.0
		idle_delay = randf_range(3.0, 6.0)

	func frame() -> int:
		return int(anims[anim][f])

	func update(dt: float, playback_rate := 1.0) -> void:
		if dt <= 0 or not is_finite(dt) or playback_rate <= 0 or not is_finite(playback_rate):
			return
		idle_delay = maxf(0.0, idle_delay - dt)
		var remaining := dt * playback_rate
		# Keep the saved phase in original 83ms units, even during longer idle holds.
		while remaining > 0:
			var duration: float = AnimationTiming.duration(sheet, anim, f, FRAME)
			var until_next := maxf(0.0, FRAME - t) * duration / FRAME
			if remaining < until_next:
				t += remaining * FRAME / duration
				break
			remaining -= until_next
			t = 0.0
			f += 1
			if f >= anims[anim].size():
				f = 0
				if next != -1:
					var n := next
					anim = -1
					play(n)


func _ready() -> void:
	G = JSON.parse_string(FileAccess.get_file_as_string("res://assets/game.json"))
	SPR = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/sprites.json"))
	_reset_world()
	graphics = GraphicsSettings.new()
	graphics.settings_path = settings_path
	add_child(graphics)
	graphics.changed.connect(_apply_graphics)
	cam = Camera2D.new()
	add_child(cam)
	get_viewport().size_changed.connect(_fit_room_to_viewport)
	_fit_room_to_viewport()
	scene_effects = SceneEffects.new()
	add_child(scene_effects)
	RenderingServer.set_default_clear_color(Color("1a120c"))
	sound = GameAudio.new()
	sound.settings_path = settings_path
	add_child(sound)
	stats = Stats.new()
	add_child(stats)
	stats.setup(settings_path, persistence_enabled)
	stats.ping(0)
	_build_ui()
	menus = GameMenu.new()
	menus.game = self
	add_child(menus)
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	_apply_graphics()
	show_home()


func _reset_world() -> void:
	scenes = G.scenes.duplicate(true)
	for key in scenes:
		for e in scenes[key].npcs:
			e.p = 0
			for a in e.interactions:
				a.done = false
			if SPR.has(e.sheet):
				e.actor = Actor.new(e.sheet, SPR[e.sheet].anims)
				e.actor.x = e.x
				e.actor.y = e.y
				e.actor.flip = e.flip
				e.actor.play(int(e.frames[0]))
	devil = Actor.new("devil", SPR.devil.anims)
	devil.x = 55
	devil.y = 196
	devil.play(0)
	cur_key = "3,2"
	inv = []
	souls = {}
	burn_msg = 44
	ev = 25                   # u.b(): вступление
	ev_wait = 0
	saved = []
	pending_pick = -2
	drop_slot = -1
	target = {}
	idle_time = 0
	tick_acc = 0
	ended = false
	follow_x = -1
	walk_previous = Vector2(NAN, NAN)
	walk_room = ""
	dialog_lines = []
	save_pending = false
	autosave_time = 0


# ---------- цикл ----------

func _fit_room_to_viewport() -> void:
	# keep_height exposes extra horizontal canvas on wide Android screens.
	# Fill it with the room; world coordinates and character silhouettes stay unchanged.
	KX = get_viewport_rect().size.x / (ROOM_W * S)
	if cam:
		cam.position = Vector2((_room().x * ROOM_W + ROOM_W / 2.0) * KX, SCENE_H / 2.0) * S
	queue_redraw()


func _process(dt: float) -> void:
	cam.position = Vector2((_room().x * ROOM_W + ROOM_W / 2.0) * KX, SCENE_H / 2.0) * S
	scene_effects.configure(cur_key, Vector2(_room().x * ROOM_W * KX * S, 0), S, KX)
	scene_effects.visible = in_game
	var soul_centers := PackedVector2Array()
	for npc in scenes[cur_key].npcs:
		if npc.has("actor") and npc.actor.sheet == "objects" and npc.actor.frame() in range(6):
			var actor: Actor = npc.actor
			var lift := 0 if npc.blocker else 10
			soul_centers.append(Vector2((_room().x * ROOM_W + actor.x) * KX, actor.y - lift - 41) * S)
	scene_effects.set_souls(soul_centers)
	queue_redraw()
	if menu_open or not in_game:
		return
	scene_effects.advance(dt)
	if devil.anim != 1 or dialog_lines.is_empty():
		devil.update(dt, KX * WALK_SPEED if devil.anim == 1 else 1.0)
	for e in scenes[cur_key].npcs:
		if e.has("actor"):
			e.actor.update(dt)
	tick_acc += dt
	while tick_acc >= TICK:
		tick_acc -= TICK
		walk_previous = Vector2(devil.x, devil.y)
		walk_room = cur_key
		_tick()
	sound.walking(dt, devil.anim == 1 and not target.is_empty() and dialog_lines.is_empty(), KX * WALK_SPEED,
		(float(devil.f) + devil.t / FRAME) / 6.0)
	_refresh_drop_buttons()
	autosave_time += dt
	if save_pending or autosave_time > 10:
		save_game()
	stats.tick(dt, souls.size())
	status_time = maxf(0, status_time - dt)
	hud_status.visible = status_time > 0


func _tick() -> void:
	for e in scenes[cur_key].npcs:
		_npc_idle(e)
	if dialog_lines.size() > 0 or not devil.free:
		return
	if ev != -1:
		if ev_wait > 0:
			ev_wait -= 1
		else:
			_run_event(ev)
			return
	if pending_pick != -2:
		_do_pick()
		return
	_walk()
	idle_time += TICK
	if idle_time > 5.0 and devil.anim == 0 and target.is_empty():
		var n := randi() % (FIDGETS.size() << 4)
		if n > 0 and n < FIDGETS.size():
			devil.play(FIDGETS[n], 0, false)


func _npc_idle(e: Dictionary) -> void:
	if not e.has("actor") or not e.actor.free or e.frames.size() < 2:
		return
	var actor: Actor = e.actor
	# Complete the gesture and return to its neutral pose before choosing another.
	if actor.idle_delay > 0 or actor.anim != int(e.frames[0]) \
		or actor.frame() != int(actor.anims[actor.anim][0]):
		return
	var n := randi_range(1, e.frames.size() - 1)
	actor.play(int(e.frames[n]), int(e.frames[0]), false)


func _walk() -> void:
	if target.is_empty():
		return
	var sc: Dictionary = scenes[cur_key]
	var dx: float = target.x - devil.x
	var step := STEP * WALK_SPEED # Original room traversal time, independent of screen width.
	var stop := absf(dx) < step
	if not stop:
		var nx := devil.x + signf(dx) * step
		devil.flip = dx < 0
		if (dx > 0 and nx >= sc.walk[1]) or (dx < 0 and nx <= sc.walk[0]) or _blocked(nx):
			stop = true
		else:
			devil.x = nx
			devil.play(1)
	if stop:
		devil.play(0)
		var t := target
		target = {}
		_arrive(t)
		if target.is_empty() and follow_x >= 0:
			var w: Array = scenes[cur_key].walk  # уже новая комната
			target = {kind = "walk", x = clampf(follow_x, w[0] + STEP, w[1] - STEP)}
			follow_x = -1.0


func _blocked(nx: float) -> bool:
	for e in scenes[cur_key].npcs:
		if e.blocker and nx > e.x - e.extent and nx < e.x + e.extent:
			return true
	return false


func _exit_open(ex: Dictionary) -> bool:
	return ex.open


func _arrive(t: Dictionary) -> void:
	match t.kind:
		"npc":
			if absf(devil.x - t.npc.x) < t.npc.radius:
				_interact(t.npc)
		"item", "drop":
			devil.play(2, 0, false)
			pending_pick = t.get("i", -1)
		"exit":
			if absf(devil.x - t.exit.x) <= 20:
				_go(t.exit.to, t.exit.spawn)
				follow_x = t.get("then_x", -1.0)  # тапнули в соседнюю комнату — после перехода идём туда


func _go(to: Array, spawn: Array) -> void:
	cur_key = "%d,%d" % [to[0], to[1]]
	devil.x = spawn[0]
	devil.y = spawn[1]
	sound.location(cur_key)
	save_pending = true
	if fade:
		fade.modulate.a = 1.0
		create_tween().tween_property(fade, "modulate:a", 0.0, 0.35)


func _room() -> Vector2i:
	var p := cur_key.split(",")
	return Vector2i(int(p[0]), int(p[1]))


# ---------- взаимодействия (k.a, ветка «огонь») ----------

func _interact(e: Dictionary) -> void:
	var acts: Array = e.interactions
	for k in range(acts.size() - 1, -1, -1):
		var a: Dictionary = acts[k]
		if a.requires_done != null and not acts[int(a.requires_done)].done:
			continue
		if a.done:
			continue
		if a.need_item != null:
			if not inv.has(int(a.need_item)):
				continue
			inv.erase(int(a.need_item))
		a.done = true
		if a.give_item != null:
			_give(int(a.give_item))
		e.free_dialogs = a.then_free_dialogs
		e.p = 0
		if a.reply != null:
			_say(a.reply)
		if a.event != null:
			ev = int(a.event)
		if e.pass_on != null and int(e.pass_on) == k:
			e.blocker = false
		_refresh_inv()
		save_pending = true
		return
	var w = _next_free(e)
	if w != null:
		_say(w)


func _next_free(e: Dictionary):  # f.b(): свободные реплики по кругу, once — один раз
	var n = e.free_dialogs
	if n == null:
		return null
	var w = null
	var tries := 0
	while true:
		if e.p < n.size():
			var d: Dictionary = n[e.p]
			e.p += 1
			if d.once and d.get("used", false):
				continue
			w = d
			if d.once:
				d.used = true
		if e.p >= n.size():
			e.p = 0
		tries += 1
		if w != null or tries >= 2:
			break
	return w


func _give(item: int) -> void:
	if inv.size() == INV_CAP:
		scenes[cur_key].floor_items.append({item = item, tx = int(devil.x / 30), ty = int(devil.y / 30)})
	else:
		inv.append(item)


func _do_pick() -> void:  # k.a: w == 2 — подобрать/положить после анимации нагиба
	var fl: Array = scenes[cur_key].floor_items
	if pending_pick == -1:
		if inv.size() > 0:
			var slot := clampi(drop_slot if drop_slot >= 0 else inv.size() - 1, 0, inv.size() - 1)
			var item: int = inv[slot]
			inv.remove_at(slot)
			fl.append({item = item, tx = int(devil.x / 30), ty = int(devil.y / 30)})
			sound.effect("drop")
	elif pending_pick < fl.size():
		var it: Dictionary = fl[pending_pick]
		fl.remove_at(pending_pick)
		if inv.size() == INV_CAP:
			fl.append({item = inv.pop_back(), tx = it.tx, ty = it.ty})
		inv.append(int(it.item))
		sound.effect("pickup")
		_say({lines = [{item = it.item}]})
	pending_pick = -2
	drop_slot = -1
	save_pending = true
	_refresh_inv()


# ---------- скрипты (u.a) ----------

func _npc(key: String, i: int) -> Dictionary:
	return scenes[key].npcs[i]


func _pose(e: Dictionary, a: int) -> void:
	e.frames = [a]
	e.actor.play(a)


func _line(text_id: int, speaker := -1, avatar := 3) -> Dictionary:
	return {speaker = G.strings[39 if speaker == -1 else speaker], avatar = avatar, text = G.strings[text_id]}


func _soul(s: String) -> void:  # u.d(): все три души — финал
	souls[s] = true
	sound.effect("soul")
	if souls.size() == 3:
		ev = 26
		ev_wait = 1


func _run_event(n: int) -> void:
	ev = -1
	save_pending = true
	match n:
		0:  # сгорел на костре — возрождение у костра
			sound.effect("burn")
			_go([3, 2], [55, 196])
			devil.play(10, 0, false)
			_say({lines = [_line(burn_msg)]})
			burn_msg = 44 if burn_msg >= 46 else burn_msg + 1
			target = {}
		1:
			var e := _npc("2,2", 0)
			e.interactions[0].done = false
			saved = [e.actor.anim, e.actor.x, e.actor.y]
			e.actor.play(2, 3, false)
			devil.play(7, 0, false)
			ev = 2
		2:
			var e := _npc("2,2", 0)
			e.actor.y = devil.y
			e.actor.x = devil.x - 30
			e.actor.play(3, saved[0], false)
			devil.play(8, 9, false)
			ev = 3
		3:
			var e := _npc("2,2", 0)
			e.actor.x = saved[1]
			e.actor.y = saved[2]
			e.actor.play(saved[0])
			devil.play(9, 0, false)
			ev = 0
		4: _npc("2,2", 0).actor.play(1)
		5: scenes["9,2"].exits[1].open = true
		6: _pose(_npc("5,1", 0), 1)
		7: _pose(_npc("4,1", 1), 5)
		8: _pose(_npc("4,1", 1), 4)
		9:
			var e := _npc("6,2", 3)
			_pose(e, 1)
			e.x = 158; e.y = 172; e.extent = 30; e.radius = 60; e.flip = true
			e.actor.x = 158; e.actor.y = 172; e.actor.flip = true
		10:
			var e := _npc("6,2", 3)
			_pose(e, 9)
			e.radius = 2
			_soul("e")
		11:
			var e := _npc("5,1", 0)
			var nm: String = e.name
			e.free_dialogs = [{once = false, lines = [_line(65), {speaker = nm, avatar = e.avatar, text = G.strings[139]},
				_line(66), {speaker = nm, avatar = e.avatar, text = G.strings[140]}]}]
			e.p = 0
		12: _pose(_npc("1,1", 0), 9)
		13:
			_pose(_npc("0,1", 0), 9)
			_soul("d")
		14:
			var e := _npc("8,1", 1)
			e.x = 190
			e.actor.x = 190
		15:
			var e := _npc("8,1", 1)
			e.interactions[0].done = false
			e.actor.play(6, 2, false)
			devil.play(12, 0, false)
			ev = 0
		16:
			_npc("8,1", 1).actor.play(3, 3, true)
			devil.play(11, 9, false)
			ev = 17
		17:
			var e := _npc("8,1", 1)
			e.actor.play(4, 5, false)
			e.frames = [5]
			e.interactions[0].done = true
			devil.play(0)
		18:
			var e := _npc("9,1", 0)
			e.actor.play(7, 8, false)
			e.frames = [8]
			devil.play(7, 0, false)
			ev = 19
		19:
			var e := _npc("9,1", 1)
			_pose(e, 2)
			e.interactions[0].done = true
		20:
			_pose(_npc("9,1", 1), 9)
			_soul("f")
		21: _pose(_npc("6,0", 0), 3)
		22: scenes["9,2"].exits[2].open = true
		23:
			_npc("0,0", 1).actor.play(5, 0, false)
			devil.play(7, 0, false)
			ev = 24
		24:
			var e := _npc("0,0", 1)
			e.frames = [4]
			e.actor.play(3, 4, false)
			devil.play(7, 0, false)
			scenes["0,0"].floor_items.append({item = 28, tx = 4, ty = 5})
		25:
			_say({lines = [_line(42, 33, 5)]})
			ev = 0
			ev_wait = 1
		26:
			_say({lines = [_line(114), _line(43, 33, 5)]})
			ended = true
		27:
			scenes["9,2"].exits[1].open = true


# ---------- ввод ----------

func _unhandled_input(event: InputEvent) -> void:
	if menu_open or not in_game:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	idle_time = 0.0
	if dialog_lines.size() > 0:
		_advance_dialog()
		return
	var g: Vector2 = get_canvas_transform().affine_inverse() * event.position / S
	g.x /= KX
	var r := _room()
	var rx := floori(g.x / ROOM_W)
	var p := Vector2(g.x - r.x * ROOM_W, g.y)
	if rx == r.x:
		target = _hit(p)
		follow_x = -1.0
		return
	var side := signi(rx - r.x)
	var sc: Dictionary = scenes[cur_key]
	for ex in sc.exits:  # тап в соседнюю комнату — идём через боковую дверь и дальше
		if _exit_open(ex) and int(ex.to[1]) == r.y and int(ex.to[0]) == r.x + side:
			target = {kind = "exit", exit = ex, x = clampf(ex.x, sc.walk[0] + STEP, sc.walk[1] - STEP),
				then_x = g.x - (r.x + side) * ROOM_W}
			return
	target = {kind = "walk", x = clampf(p.x, sc.walk[0] + STEP, sc.walk[1] - STEP)}


func _hit(p: Vector2) -> Dictionary:
	var sc: Dictionary = scenes[cur_key]
	var lo: float = sc.walk[0] + STEP
	var hi: float = sc.walk[1] - STEP
	var fl: Array = sc.floor_items
	for i in range(fl.size() - 1, -1, -1):
		if Rect2(fl[i].tx * 30 - 5, fl[i].ty * 30 - 5, 40, 40).has_point(p):
			return {kind = "item", i = i, x = clampf(fl[i].tx * 30 + 15, lo, hi)}
	var npcs: Array = sc.npcs
	for pass_ in [true, false]:  # сначала видимые спрайты, потом невидимые хотспоты
		for i in range(npcs.size() - 1, -1, -1):
			var e: Dictionary = npcs[i]
			if e.has("actor") != pass_ or not _npc_rect(e).has_point(p):
				continue
			var side := -1.0 if devil.x < e.x else 1.0
			var r: float = maxf(e.radius - 6, 0)
			return {kind = "npc", npc = e, x = clampf(e.x + side * minf(r, absf(devil.x - e.x)), lo, hi)}
		if pass_:
			for ex in sc.exits:
				if _exit_open(ex) and _exit_rect(ex).has_point(p):
					return {kind = "exit", exit = ex, x = clampf(ex.x, lo, hi)}
	return {kind = "walk", x = clampf(p.x, lo, hi)}


func _exit_rect(ex: Dictionary) -> Rect2:
	if cur_key == "9,2":
		if int(ex.to[0]) == 2 and int(ex.to[1]) == 1:
			return Rect2(34, 114, 46, 42)  # original low arched cellar gate
		if int(ex.to[0]) == 4 and int(ex.to[1]) == 0:
			return Rect2(199, 63, 41, 119)  # recessed main monastery entrance
	return Rect2(ex.x - 25, ex.y - 80, 50, 100)


func _npc_rect(e: Dictionary) -> Rect2:
	if not e.has("actor"):
		if cur_key == "9,2":
			if int(e.x) == 58:
				return _exit_rect(scenes[cur_key].exits[1])
			if int(e.x) == 210:
				return _exit_rect(scenes[cur_key].exits[2])
		var w: float = maxf(e.extent, 10) + 10
		return Rect2(e.x - w, e.y - 30, w * 2, 60)
	var a: Actor = e.actor
	var tx := _orig("%s/%d" % [a.sheet, a.frame()])
	var anc: Array = SPR[a.sheet].anchors[a.frame()]
	var lift := 0 if e.blocker else 10
	if tx.get_width() <= 1 and tx.get_height() <= 1:
		# Пустой кадр (Дона Анна в могиле): спрайта нет, тапаем по кресту на фоне вместе с глазком над ним.
		# В HD крест на 14 левее оригинала — хитбокс накрывает оба.
		return Rect2(e.x - 34, e.y - lift - 92, 48, 120)
	var left: float = a.x - (tx.get_width() - anc[0] if a.flip else anc[0]) / KX
	return Rect2(Vector2(left, a.y - lift - anc[1]) + _actor_visual_offset(a), tx.get_size() / Vector2(KX, 1))


# ---------- отрисовка ----------

func _pack_path(relative: String) -> String:
	var base: String = graphics.texture_root if graphics != null else "res://assets/hd"
	var selected := base.path_join(relative)
	if ResourceLoader.exists(selected) or FileAccess.file_exists(selected):
		return selected
	return "res://assets/hd/" + relative


func _apply_graphics() -> void:
	graphics.apply_viewport(get_viewport())
	texture_filter = graphics.texture_filter
	tex_cache.clear()
	background_cache_path = ""
	var metadata := _pack_path("hd.json")
	hd = JSON.parse_string(FileAccess.get_file_as_string(metadata)) if FileAccess.file_exists(metadata) else {}
	if scene_effects:
		scene_effects.set_quality(graphics.effects_level)
	actor_shadows.set_quality(graphics.effects_level)
	if not ui_slots.is_empty():
		_refresh_inv()
	if ui_dialog != null and ui_dialog.visible and not dialog_lines.is_empty():
		var line: Dictionary = dialog_lines[0]
		ui_avatar.texture = _tex("artifacts/%d" % line.item if line.has("item") else "avatars/%d" % line.avatar)
	if menus != null and menus.is_inside_tree() and menus.page == "home":
		menus.show_page("home")
	queue_redraw()


func _tex(path: String) -> Texture2D:
	var relative := path.trim_prefix("hd/").trim_prefix("qhd/")
	var resource_path := _pack_path(relative + ".png")
	if not ResourceLoader.exists(resource_path):
		resource_path = "res://assets/%s.png" % relative if relative.begins_with("scenes/") else "res://assets/sprites/%s.png" % relative
	if not tex_cache.has(resource_path):
		# A room is a large uncompressed GPU texture. Release its cache reference on travel.
		if relative.begins_with("scenes/"):
			tex_cache.erase(background_cache_path)
			background_cache_path = resource_path
		tex_cache[resource_path] = load(resource_path)
	return tex_cache[resource_path]


func _orig(path: String) -> Texture2D:  # исходный спрайт — по нему размеры и хитбоксы
	return load("res://assets/sprites/%s.png" % path)


func _bg(key: String) -> Texture2D:
	return _tex("scenes/" + key.replace(",", "_"))


func _actor_visual_offset(a: Actor) -> Vector2:
	# Interpolate the hero's 20Hz movement at display refresh rate. Teleports stay instant.
	if a == devil and in_game and walk_room == cur_key and is_finite(walk_previous.x) \
		and is_equal_approx(a.y, walk_previous.y) and absf(a.x - walk_previous.x) <= STEP:
		return Vector2(lerpf(walk_previous.x, a.x, clampf(tick_acc / TICK, 0, 1)) - a.x, 0)
	# The widened bell chamber has its cot farther right than the old pixel-art anchor.
	# Keep all sleep/wake poses and their tap bounds together; quest coordinates stay stable.
	if cur_key == "0,0" and a.sheet == "mon":
		return Vector2(20, 3)
	return Vector2.ZERO


func _draw_actor(a: Actor, ox: float, lift := 0) -> void:
	var fr := a.frame()
	var offset := _actor_visual_offset(a)
	draw_set_transform(Vector2((ox + a.x + offset.x) * KX, a.y + offset.y - lift) * S, 0, Vector2(-S if a.flip else S, S))
	if hd.has(a.sheet):  # перерисованный лист: общий холст, якорь в единицах оригинала
		var h: Dictionary = hd[a.sheet]
		draw_texture_rect(_tex("hd/%s/%d" % [a.sheet, fr]),
			Rect2(-h.anchor[0], -h.anchor[1], h.canvas[0], h.canvas[1]), false)
	else:
		var anc: Array = SPR[a.sheet].anchors[fr]
		draw_texture(_tex("%s/%d" % [a.sheet, fr]), Vector2(-anc[0], -anc[1]))


func _draw() -> void:
	var r := _room()
	for key in [cur_key]:
		var sc: Dictionary = scenes[key]
		var ox: float = r.x * ROOM_W
		draw_set_transform(Vector2(ox * KX * S, 0), 0, Vector2(S, S))
		draw_texture_rect(_bg(key), Rect2(0, 0, ROOM_W * KX, SCENE_H), false)
		for it in sc.floor_items:
			var sz := _orig("artifacts/%d" % it.item).get_size()
			var c := Vector2((it.tx * 30 + 15) * KX, it.ty * 30 + 15)
			draw_texture_rect(_tex("artifacts/%d" % it.item), Rect2(c - sz / 2, sz), false)
		if key == cur_key:
			for ex in sc.exits:
				if _exit_open(ex):
					_draw_arrow(ex, ox)
		for e in sc.npcs:
			if e.has("actor"):
				actor_shadows.draw_actor_shadow(self, e.actor, ox, 0 if e.blocker else 10, hd, S, KX, key)
		actor_shadows.draw_actor_shadow(self, devil, ox, 0, hd, S, KX, key)
		for e in sc.npcs:
			if e.has("actor"):
				_draw_actor(e.actor, ox, 0 if e.blocker else 10)
		_draw_eyes(key, ox)
	_draw_actor(devil, r.x * ROOM_W)


func _draw_eyes(key: String, ox: float) -> void:
	var tick := int(Time.get_ticks_msec() / (FRAME * 1000))
	var npcs: Array = scenes[key].npcs
	for i in npcs.size():
		var e: Dictionary = npcs[i]
		if e.sheet != "virtual":
			continue
		var seq: Array = EYE_ANIMS[int(e.frames[0])]
		var fr: int = seq[tick % seq.size()]
		if fr == 2:
			continue
		var at: Vector2 = Vector2(e.x, e.y - (0 if e.blocker else 10)) + EYE_SHIFT.get("%s/%d" % [key, i], Vector2.ZERO)
		draw_set_transform(Vector2((ox + at.x) * KX, at.y) * S, 0, Vector2(S, S))
		draw_texture_rect_region(_eye_tex, Rect2(-12, -7, 25, 16), Rect2(fr * 200, 0, 200, 128))


func _draw_arrow(ex: Dictionary, ox: float) -> void:
	var dir := Vector2.UP if ex.y < 150 else Vector2.DOWN if ex.y > 200 else Vector2.LEFT if ex.x < 120 else Vector2.RIGHT
	var c := Vector2(clampf(ex.x, 8, 232), ex.y - 40 if dir.y == 0 else ex.y - 20)
	if cur_key == "9,2" and int(ex.to[0]) in [2, 4]:
		dir = Vector2.UP
		var door := _exit_rect(ex)
		c = Vector2(ex.x, door.end.y - 8)
	var n := Vector2(-dir.y, dir.x)
	c.x *= KX
	draw_set_transform(Vector2(ox * KX * S, 0), 0, Vector2(S, S))
	draw_colored_polygon([c + dir * 6, c - dir * 3 + n * 5, c - dir * 3 - n * 5], Color(1, 0.85, 0.4, 0.55))


# ---------- UI ----------

func _build_ui() -> void:
	var art_theme = preload("res://scripts/art_theme.gd")
	var theme: Theme = art_theme.theme()
	var layer := CanvasLayer.new()
	game_layer = layer
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.modulate.a = 0.0
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(fade)
	var box: StyleBoxFlat = art_theme.panel(Color(0.045, 0.060, 0.059, 0.96))
	ui_dialog = Panel.new()
	ui_dialog.theme = theme
	ui_dialog.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ui_dialog.add_theme_stylebox_override("panel", box)
	ui_dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_dialog.anchor_left = 0.0
	ui_dialog.anchor_right = 1.0
	ui_dialog.anchor_top = 1.0
	ui_dialog.anchor_bottom = 1.0
	ui_dialog.offset_left = 16
	ui_dialog.offset_right = -16
	ui_dialog.offset_top = -192
	ui_dialog.offset_bottom = -12
	layer.add_child(ui_dialog)
	art_theme.decorate(ui_dialog, 8)
	var portrait_frame := Panel.new()
	portrait_frame.position = Vector2(16, 18)
	portrait_frame.size = Vector2(144, 144)
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_theme_stylebox_override("panel", art_theme.panel(Color("282b24"), art_theme.BRASS, 0))
	ui_dialog.add_child(portrait_frame)
	art_theme.decorate(portrait_frame, 5, true)
	ui_avatar = TextureRect.new()
	ui_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_avatar.position = Vector2(10, 10)
	ui_avatar.size = Vector2(124, 124)
	ui_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ui_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_frame.add_child(ui_avatar)
	ui_name = Label.new()
	ui_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_name.position = Vector2(180, 9)
	ui_name.add_theme_font_override("font", art_theme.TITLE_FONT)
	ui_name.add_theme_font_size_override("font_size", 30)
	ui_name.add_theme_color_override("font_color", Color("e4bf7c"))
	ui_dialog.add_child(ui_name)
	var divider := ColorRect.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.color = Color("61583e")
	divider.anchor_right = 1.0
	divider.offset_left = 180
	divider.offset_right = -22
	divider.offset_top = 51
	divider.offset_bottom = 52
	ui_dialog.add_child(divider)
	ui_text = Label.new()
	ui_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_text.anchor_right = 1.0
	ui_text.anchor_bottom = 1.0
	ui_text.offset_left = 180
	ui_text.offset_top = 58
	ui_text.offset_right = -22
	ui_text.offset_bottom = -33
	ui_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_text.add_theme_font_size_override("font_size", 32)
	ui_text.add_theme_constant_override("line_spacing", 2)
	ui_dialog.add_child(ui_text)
	# Long original monologues grow the panel upward, keeping the full text above the tap hint.
	ui_text.minimum_size_changed.connect(func():
		ui_dialog.offset_top = -maxf(192.0, ui_text.get_minimum_size().y + 103.0))
	ui_dialog.resized.connect(func():
		portrait_frame.position.y = (ui_dialog.size.y - portrait_frame.size.y) * 0.5)
	var next_hint := Label.new()
	next_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_hint.text = "Далее   ›"
	next_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	next_hint.anchor_right = 1.0
	next_hint.anchor_top = 1.0
	next_hint.anchor_bottom = 1.0
	next_hint.offset_left = 180
	next_hint.offset_right = -40
	next_hint.offset_top = -29
	next_hint.offset_bottom = -4
	next_hint.add_theme_font_size_override("font_size", 19)
	next_hint.add_theme_color_override("font_color", art_theme.MUTED)
	ui_dialog.add_child(next_hint)
	var slot_box: StyleBoxFlat = art_theme.panel(Color(0.07, 0.095, 0.087, 0.86))
	for i in INV_CAP:
		var slot := Panel.new()
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		slot.add_theme_stylebox_override("panel", slot_box)
		slot.anchor_left = 1.0
		slot.anchor_right = 1.0
		slot.offset_left = -190  # столбиком в правом поле рядом с комнатой
		slot.offset_right = -20
		slot.offset_top = 20 + i * 250
		slot.offset_bottom = slot.offset_top + 170
		art_theme.decorate(slot, 8, true)
		var slot_hint := Label.new()
		slot_hint.text = "I" if i == 0 else "II"
		slot_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slot_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_hint.add_theme_font_override("font", art_theme.TITLE_FONT)
		slot_hint.add_theme_font_size_override("font_size", 48)
		slot_hint.add_theme_color_override("font_color", Color(0.63, 0.60, 0.43, 0.20))
		slot_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(slot_hint)
		var b := TextureButton.new()
		b.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.offset_left = 20
		b.offset_top = 20
		b.offset_right = -20
		b.offset_bottom = -20
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.pressed.connect(_on_slot.bind(i))
		slot.add_child(b)
		layer.add_child(slot)
		ui_slots.append(b)
		var drop := Button.new()
		drop.theme = theme
		drop.text = "Положить"
		drop.add_theme_font_size_override("font_size", 26)
		drop.anchor_left = 1.0
		drop.anchor_right = 1.0
		drop.offset_left = -190
		drop.offset_right = -20
		drop.offset_top = slot.offset_bottom + 6
		drop.offset_bottom = drop.offset_top + 64
		drop.pressed.connect(_drop_item.bind(i))
		layer.add_child(drop)
		drop_buttons.append(drop)
	var pause := Button.new()
	pause.theme = theme
	pause.text = "☰  Меню"
	pause.position = Vector2(24, 24)
	pause.size = Vector2(195, 76)
	pause.add_theme_font_size_override("font_size", 32)
	pause.pressed.connect(pause_game)
	layer.add_child(pause)
	hud_status = Label.new()
	hud_status.theme = theme
	hud_status.position = Vector2(24, 115)
	hud_status.add_theme_font_size_override("font_size", 26)
	hud_status.add_theme_color_override("font_color", art_theme.PAPER)
	hud_status.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud_status.add_theme_constant_override("shadow_offset_x", 2)
	hud_status.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(hud_status)
	ui_dialog.hide()


func _refresh_inv() -> void:
	for i in INV_CAP:
		ui_slots[i].texture_normal = _tex("artifacts/%d" % inv[i]) if i < inv.size() else null
	_refresh_drop_buttons()


func _refresh_drop_buttons() -> void:
	for i in drop_buttons.size():
		drop_buttons[i].disabled = i >= inv.size() or not devil.free or not dialog_lines.is_empty() \
			or ev != -1 or pending_pick != -2 or menu_open


func _drop_item(i: int) -> void:
	if menu_open or not in_game or i >= inv.size() or i < 0 or not devil.free \
		or not dialog_lines.is_empty() or ev != -1 or pending_pick != -2:
		return
	drop_slot = i
	target = {}
	follow_x = -1
	_arrive({kind = "drop"})
	save_pending = true
	_refresh_drop_buttons()


func _on_slot(i: int) -> void:
	if menu_open or not in_game:
		return
	if dialog_lines.size() > 0:
		_advance_dialog()
	elif i < inv.size():
		_say({lines = [{item = inv[i]}]})


func _say(w: Dictionary) -> void:
	dialog_lines = w.lines.duplicate()
	save_pending = true
	_show_line()


func _show_line() -> void:
	var l: Dictionary = dialog_lines[0]
	if l.has("item"):
		var it: Dictionary = G.items[int(l.item)]
		ui_avatar.texture = _tex("artifacts/%d" % l.item)
		ui_name.text = it.name
		ui_text.text = it.desc
	else:
		ui_avatar.texture = _tex("avatars/%d" % l.avatar)
		ui_name.text = l.speaker
		ui_text.text = l.text
	ui_dialog.show()
	sound.say(l)
	_refresh_drop_buttons()


func _advance_dialog() -> void:
	sound.stop_voice()
	dialog_lines.pop_front()
	save_pending = true
	if dialog_lines.size() > 0:
		_show_line()
		return
	ui_dialog.hide()
	if ended:
		save_game()
		in_game = false
		show_home()
		menus.message("Три души собраны. Сделка исполнена!")


# ---------- меню, сохранения и жизненный цикл Android ----------

func has_save() -> bool:
	return not SaveStore.read(save_path, self).is_empty()


func new_game() -> void:
	_reset_world()
	in_game = true
	ui_dialog.hide()
	sound.stop_voice()
	_refresh_inv()
	resume_game()
	save_game()


func continue_game() -> bool:
	var data := SaveStore.read(save_path, self)
	if data.is_empty():
		menus.message("Сохранение не найдено или повреждено.")
		return false
	SaveStore.restore(data, self)
	in_game = true
	_refresh_inv()
	resume_game()
	if not dialog_lines.is_empty():
		_show_line()
	else:
		ui_dialog.hide()
		if ended:
			in_game = false
			show_home()
			menus.message("Игра пройдена. Можно начать новое приключение.")
	return true


func save_game() -> bool:
	if not in_game or not persistence_enabled:
		save_pending = false
		autosave_time = 0
		return true
	var error := SaveStore.write(save_path, self)
	save_pending = false
	autosave_time = 0
	if error != OK:
		hud_status.text = "Не удалось сохранить игру"
		status_time = 5
		return false
	return true


func pause_game() -> void:
	if not in_game or menu_open:
		return
	menu_open = true
	var ok := save_game()
	stats.ping(souls.size())
	game_layer.visible = false
	sound.pause_voice(true)
	menus.show_page("pause")
	if not ok:
		menus.message("Не удалось сохранить игру. Прогресс пока остаётся в памяти.")


func resume_game() -> void:
	menu_open = false
	menus.hide()
	game_layer.visible = true
	sound.pause_voice(false)
	sound.location(cur_key)
	_refresh_drop_buttons()


func show_home() -> void:
	menu_open = true
	game_layer.visible = false
	sound.stop_voice()
	sound.location(cur_key, true)
	menus.show_page("home")


func return_home() -> void:
	if not save_game():
		menus.message("Не удалось сохранить игру. Освободите место и повторите.")
		return
	in_game = false
	show_home()


func quit_game() -> void:
	if quitting:
		return
	if not save_game():
		pause_game()
		menus.message("Не удалось сохранить игру. Освободите место и повторите.")
		return
	quitting = true
	menu_open = true
	sound.shutdown()
	# AudioServer releases stopped playback objects on the following mixer ticks.
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


func _back() -> void:
	if menu_open:
		menus.back()
	else:
		pause_game()


func _notification(what: int) -> void:
	if menus == null or sound == null:
		return
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_back()
		NOTIFICATION_WM_CLOSE_REQUEST:
			quit_game()
		NOTIFICATION_APPLICATION_PAUSED:
			pause_game()
			save_game()
			sound.suspend(true)
		NOTIFICATION_APPLICATION_RESUMED:
			sound.suspend(false)
			sound.pause_voice(menu_open)
