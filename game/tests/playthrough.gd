extends SceneTree
## Прохождение «как игрок»: только экранные тапы по стрелкам дверей, персонажам и предметам,
## ходьба пешком, путь между комнатами ищется по открытым дверям. Ловит то, что walkthrough.gd
## пропускает телепортом: перекрытые хитбоксы, недоходы до дверей, блокеры.
## Действия делаются тапом в случайную видимую точку цели, а в каждой комнате все видимые пиксели
## персонажей, предметов, стрелок и «глазков» прощупываются сеткой: куда тап попал на самом деле.
## godot --headless --path game --script res://tests/playthrough.gd -- [--width=2520] [--seed=1] [--report=/tmp/taps.json]

const STRIDE := 2.0  # шаг сетки в единицах оригинала (~10 px на экране 1080p)
var m
var failed := false
var taps := 0
var width := 1920
var report_path := ""
var rng := RandomNumberGenerator.new()
var images := {}     # путь -> Image (альфа для «видимо ли»)
var probes := {}     # комната|цель|кадр -> {points, miss, instead}
var fallbacks: Array = []  # действия, где случайная видимая точка не сработала и пришлось тапать в центр


func _initialize() -> void:
	start.call_deferred()


func start() -> void:
	rng.seed = 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--width="):
			width = int(a.trim_prefix("--width="))
		elif a.begins_with("--seed="):
			rng.seed = int(a.trim_prefix("--seed="))
		elif a.begins_with("--report="):
			report_path = a.trim_prefix("--report=")
	var vp := SubViewport.new()
	vp.size = Vector2i(width, 1080)
	root.add_child(vp)
	m = load("res://main.tscn").instantiate()
	m.persistence_enabled = false
	m.save_path = "user://playthrough_unused.json"
	m.settings_path = "user://playthrough_settings_unused.cfg"
	vp.add_child(m)
	m.new_game()
	m.set_process(false)
	run()
	await create_timer(0.3).timeout
	m.sound.shutdown()
	await create_timer(0.3).timeout
	m.queue_free()
	await process_frame
	quit(1 if failed else 0)


func check(condition: bool, message: String) -> bool:
	if not condition:
		failed = true
		push_error(message)
	return condition


func run() -> void:
	idle()
	var steps := [
		["take", "9,2", 19], ["use", "7,2", 0],                         # рупор смотрителю
		["take", "8,2", 13], ["use", "7,2", 0],                         # очки смотрителю
		["take", "7,2", 27], ["use", "2,2", 0],                         # лопата палачу -> топор
		["use", "7,2", 0], ["use", "9,2", 0],                           # топор -> ключ, подвал открыт
		["use", "0,2", 1], ["use", "0,2", 1],                           # виноград, ещё виноград
		["use", "4,1", 1], ["use", "5,1", 0], ["use", "4,1", 1],        # сок; пустая бутыль; вино
		["use", "5,1", 0],                                              # первое вино -> бутыль обратно
		["use", "4,1", 1], ["use", "4,1", 1], ["use", "5,1", 0],        # второе вино -> Ключник пропускает
		["take", "1,0", 15], ["use", "6,2", 3], ["use", "6,2", 3],      # молот -> Дона Анна
		["use", "1,0", 0], ["use", "3,0", 0], ["use", "5,1", 0],        # сера, бутыль, масло
		["use", "3,0", 0], ["use", "3,0", 0],                           # масло, сера -> динамит
		["use", "1,1", 0], ["use", "0,1", 0],                           # взрыв -> Чернокнижник
		["take", "0,1", 7], ["use", "3,0", 0],                          # побочное: амулет алхимику,
		["use", "8,1", 0], ["use", "3,0", 0],                           # манускрипт у настоятеля -> подсказка про робота
		["take", "5,2", 26], ["use", "1,2", 0],                         # серп -> лист папоротника
		["take", "9,2", 30], ["use", "6,0", 0],                         # Венера в руки; лист курильщику
		["use", "4,0", 0],                                              # Венера -> Квазимодо пропускает
		["take", "2,0", 22], ["take", "4,0", 10],                       # котелок, удочка
		["use", "4,2", 0], ["use", "4,2", 0],                           # котелок с водой, рыба
		["use", "9,0", 0], ["use", "9,0", 1], ["use", "9,0", 1],        # повар, рыба на блюде
		["use", "8,0", 0],
		["take", "8,0", 25], ["use", "0,2", 0], ["use", "8,0", 0],      # молоко -> сыр
		["use", "7,1", 0], ["use", "8,1", 1],                           # мышь настоятелю
		["take", "0,1", 6], ["use", "8,1", 1],                          # эликсир -> пропускает
		["take", "1,2", 31], ["use", "9,1", 0],                         # деталь роботу
		["take", "6,1", 24], ["use", "0,0", 1],                         # верёвка -> ключ на 12
		["take", "0,0", 28], ["use", "9,1", 0], ["use", "9,1", 1],      # робот -> Послушник
		["talk", "0,3", 0], ["talk", "0,3", 1], ["talk", "1,3", 0],     # ад: паладин, кочегар, секретарь
		["take", "1,3", 32], ["use", "0,3", 1],                         # кочерга -> талон
		["use", "1,3", 0], ["use", "1,3", 1],                           # талон -> ковёр у Люцифера
		# глава 2 «Недостача»: выбор ответа, нарочно неверные — проверка провалов
		["talk", "3,3", 0], ["choose", "2,3", 0, 2],                  # Цербер не пускает; излишек ребра
		["fail", "3,3", 0, 0], ["choose", "3,3", 0, 2],              # кость левой голове — покусали; между головами
		["take", "3,3", 36], ["take", "3,3", 37], ["use", "2,3", 0],  # перо, сосуд; перо -> командировочное
		["choose", "2,3", 1, 2], ["use", "4,3", 0], ["choose", "4,3", 0, 2],   # печать; обол; «смотреть в оба»
		["use", "5,3", 0],                                            # Харон
		["use", "2,4", 0], ["take", "3,4", 40], ["use", "6,4", 0],    # слеза; крыса; конец шутки
		["fail", "5,4", 0, 0], ["choose", "5,4", 0, 1],              # не та концовка — темница; правильная
		["use", "1,4", 0], ["use", "4,4", 0], ["use", "4,4", 0],      # мандрагора; два ингредиента
		["use", "2,4", 0], ["use", "1,4", 0], ["use", "3,4", 0],      # ангел трезвеет; золото; маска
		["choose", "2,4", 1, 2], ["use", "2,4", 0],                   # нимб; полёт
		["choose", "0,5", 0, 1], ["take", "2,5", 49], ["use", "2,5", 0],   # экзамен Петра; яблоко -> ключ
		["choose", "1,5", 0, 2], ["take", "3,5", 51],                 # «ревизия»; чернильница
		["fail", "3,5", 0, 0], ["choose", "3,5", 0, 2],              # разбил часы — откат; перевернул
		["talk", "4,5", 1], ["use", "4,5", 0], ["sign", "", 0],         # кресло; книга; договор
	]
	for s in steps:
		if failed:
			return
		if s[0] == "take":
			take(s[1], s[2])
		elif s[0] == "talk":
			talk(s[1], s[2])
		elif s[0] == "choose":
			choose(s[1], s[2], s[3], true)
		elif s[0] == "fail":
			choose(s[1], s[2], s[3], false)
		elif s[0] == "sign":
			sign_contract()
		else:
			use(s[1], s[2])
	if not failed:
		idle()
	if not check(m.souls.size() == 3 and m.ended, "финал не наступил: души %s" % [m.souls.keys()]):
		return
	check(m.menus.page == "sequel", "после финала нет окна «Продолжение следует»: %s" % m.menus.page)
	var doors := all_doors()
	report()
	if not failed:
		print("PLAYTHROUGH OK: %d тапов, %d мин игрового времени, дверей проверено %d" % [taps, int(m.stats.play / 60), doors])


func all_doors() -> int:  # каждая открытая дверь с тапа по стрелке, из пяти точек комнаты
	m.ended = false
	m.in_game = true    # после финала игра ушла в меню — возвращаемся бродить по открытому миру
	m.resume_game()
	var n := 0
	for key in m.scenes:
		var sc: Dictionary = m.scenes[key]
		for i in sc.exits.size():
			if not sc.exits[i].open:
				continue
			for k in 5:
				m.cur_key = key
				m.target = {}
				m.devil.x = lerpf(sc.walk[0] + m.STEP, sc.walk[1] - m.STEP, (k + 0.37) / 5.0)
				if m._blocked(m.devil.x):
					continue
				var ex: Dictionary = sc.exits[i]
				var to := "%d,%d" % [ex.to[0], ex.to[1]]
				var start_x: float = m.devil.x
				aim({kind = "exit", exit = ex}, m._arrow(ex)[0], "стрелка → " + to)
				idle()
				n += 1
				if not check(m.cur_key == to, "дверь %s -> %s не сработала: старт x=%.1f, стоп x=%.1f" % [key, to, start_x, m.devil.x]):
					return n
	return n


# ---------- «палец» ----------

func tap(p: Vector2) -> void:  # p — координаты внутри текущей комнаты, как у _hit
	var r: Vector2i = m._room()
	var world: Vector2 = Vector2((r.x * m.ROOM_W + p.x) * m.KX, p.y) * m.S
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = m.get_canvas_transform() * world
	taps += 1
	m._unhandled_input(ev)


func idle(limit := 2400) -> void:  # 2 минуты игры на шаг максимум
	for i in limit:
		if m.dialog_lines.size() > 0:
			tap(Vector2(120, 100))  # листаем диалог тапом
			continue
		m._process(0.05)
		if m.target.is_empty() and m.ev == -1 and m.devil.free and m.pending_pick == -2 \
			and m.dialog_lines.is_empty() and m.follow_x < 0:
			return
	check(false, "не успокоилось на %s: ev=%d target=%s" % [m.cur_key, m.ev, m.target])


# ---------- навигация ----------

func path_to(key: String) -> Array:  # BFS по открытым дверям: список индексов выходов
	var prev := {m.cur_key: null}
	var queue := [m.cur_key]
	while not queue.is_empty():
		var k: String = queue.pop_front()
		if k == key:
			break
		var exits: Array = m.scenes[k].exits
		for i in exits.size():
			var to := "%d,%d" % [exits[i].to[0], exits[i].to[1]]
			if exits[i].open and not prev.has(to):
				prev[to] = [k, i]
				queue.append(to)
	if not prev.has(key):
		return []
	var path := []
	var k := key
	while prev[k] != null:
		path.push_front(prev[k][1])
		k = prev[k][0]
	return path


func goto(key: String) -> bool:
	if m.cur_key == key:
		return true
	var path := path_to(key)
	if not check(not path.is_empty(), "нет пути %s -> %s" % [m.cur_key, key]):
		return false
	for i in path:
		var ex: Dictionary = m.scenes[m.cur_key].exits[i]
		var from: String = m.cur_key
		var to := "%d,%d" % [ex.to[0], ex.to[1]]
		aim({kind = "exit", exit = ex}, m._arrow(ex)[0], "стрелка → " + to)
		idle()
		if not check(m.cur_key == to, "дверь %s -> %s не сработала с тапа по стрелке (чёрт на x=%.1f, цель %s)" \
				% [from, to, m.devil.x, m._hit(m._arrow(ex)[0]).get("kind")]):
			return false
	return true


func center(r: Rect2) -> Vector2:
	return r.position + r.size / 2


func take(key: String, item: int) -> void:
	if not goto(key):
		return
	var fl: Array = m.scenes[key].floor_items
	for j in fl.size():
		var it: Dictionary = fl[j]
		if int(it.item) == item:
			aim({kind = "item", i = j}, Vector2(it.tx * 30 + 15, it.ty * 30 + 15), "предмет %d" % item)
			idle()
			check(m.inv.has(item), "%s: предмет %d не подобрался тапом, в руках %s" % [key, item, m.inv])
			return
	check(false, "на %s нет предмета %d" % [key, item])


func use(key: String, i: int) -> void:
	if not goto(key):
		return
	var e: Dictionary = m._npc(key, i)
	var before := 0
	for a in e.interactions:
		before += int(a.done)
	var souls_before: int = m.souls.size()
	aim({kind = "npc", npc = e}, center(m._npc_rect(e)), e.get("name", "?"))
	var hit_npc: bool = m.target.get("npc", {}) == e
	idle()
	var after := 0
	for a in e.interactions:
		after += int(a.done)
	check(after > before or m.souls.size() > souls_before,
		"%s#%d (%s): тап не сработал (цель тапа — %s), в руках %s" % [key, i, e.name, "он" if hit_npc else "другое", m.inv])


func talk(key: String, i: int) -> void:  # персонаж только разговаривает: тап должен открыть диалог
	if not goto(key):
		return
	var e: Dictionary = m._npc(key, i)
	aim({kind = "npc", npc = e}, center(m._npc_rect(e)), e.get("name", "?"))
	var spoke := false
	for step in 2400:
		if m.dialog_lines.size() > 0:
			spoke = true
			break
		m._process(0.05)
		if m.target.is_empty() and m.devil.free:
			spoke = m.dialog_lines.size() > 0
			break
	check(spoke, "%s#%d (%s): тап не открыл разговор" % [key, i, e.name])
	idle()


func sign_contract() -> void:  # тап по кнопке «Отказаться» в окне договора — как игрок
	if not check(m.menus.page == "contract", "нет окна договора: %s" % m.menus.page):
		return
	for b in m.menus.column.get_children():
		if b is Button and b.text == "Отказаться":
			taps += 1
			b.pressed.emit()
			idle()
			return
	check(false, "в окне договора нет кнопки «Отказаться»")


func choose(key: String, i: int, option: int, ok: bool) -> void:  # тап по персонажу, затем по кнопке ответа
	if not goto(key):
		return
	var e: Dictionary = m._npc(key, i)
	var before := 0
	for a in e.interactions:
		before += int(a.done)
	var had: Array = m.inv.duplicate()
	aim({kind = "npc", npc = e}, center(m._npc_rect(e)), e.get("name", "?"))
	idle()
	if not check(m.menus.page == "choice", "%s#%d (%s): нет выбора ответа, в руках %s" % [key, i, e.name, m.inv]):
		return
	var buttons: Array = m.menus.column.get_children().filter(func(b): return b is Button)
	taps += 1
	buttons[option].pressed.emit()
	idle()
	var after := 0
	for a in e.interactions:
		after += int(a.done)
	if ok:
		check(after > before, "%s#%d (%s): верный ответ не засчитан" % [key, i, e.name])
	else:
		check(after == before and m.inv == had, "%s#%d (%s): неверный ответ засчитан или съел предмет" % [key, i, e.name])


# ---------- щуп: видимые пиксели целей и куда в них попадает тап ----------
# Цель — то, что нарисовано в комнате: {key, label, expect, at, draw, flip, path, region | poly}.
# at/draw — в экранных единицах комнаты (x уже умножен на KX), как в main._draw.

func targets() -> Array:  # в порядке отрисовки: верхняя цель — последняя
	var out := []
	var sc: Dictionary = m.scenes[m.cur_key]
	for i in sc.floor_items.size():
		var it: Dictionary = sc.floor_items[i]
		var sz: Vector2 = m._orig("artifacts/%d" % it.item).get_size()
		out.append({label = "предмет «%s»" % m.G.items[int(it.item)].name, expect = {kind = "item", i = i},
			at = Vector2((it.tx * 30 + 15) * m.KX, it.ty * 30 + 15), draw = Rect2(-sz / 2, sz), flip = false,
			path = m._pack_path("artifacts/%d.png" % it.item)})
	for ex in sc.exits:
		if not m._exit_open(ex):
			continue
		var arrow: Array = m._arrow(ex)
		var c: Vector2 = arrow[0]
		var dir: Vector2 = arrow[1]
		var n := Vector2(-dir.y, dir.x)
		c.x *= m.KX
		var poly := PackedVector2Array([c + dir * 6, c - dir * 3 + n * 5, c - dir * 3 - n * 5])
		out.append({label = "стрелка → %d,%d" % [ex.to[0], ex.to[1]], expect = {kind = "exit", exit = ex},
			poly = poly, draw = Rect2(c - Vector2(7, 7), Vector2(14, 14)), at = Vector2.ZERO, flip = false})
	for i in sc.npcs.size():
		var e: Dictionary = sc.npcs[i]
		if not e.has("actor"):
			continue
		var a = e.actor
		var fr: int = a.frame()
		var orig: Texture2D = m._orig("%s/%d" % [a.sheet, fr])
		if orig.get_width() <= 1 and orig.get_height() <= 1:
			continue  # пустой кадр (Дона Анна в могиле) — её ловят «глазки»
		var off: Vector2 = m._actor_visual_offset(a)
		var t := {label = "%s (%s кадр %d)" % [e.get("name", "?"), a.sheet, fr], expect = {kind = "npc", npc = e},
			at = Vector2((a.x + off.x) * m.KX, a.y + off.y - (0 if e.blocker else 10)), flip = a.flip}
		if m.hd.has(a.sheet):
			var h: Dictionary = m.hd[a.sheet]
			t.draw = Rect2(-h.anchor[0], -h.anchor[1], h.canvas[0], h.canvas[1])
			t.path = m._pack_path("%s/%d.png" % [a.sheet, fr])
		else:
			var anc: Array = m.SPR[a.sheet].anchors[fr]
			t.draw = Rect2(Vector2(-anc[0], -anc[1]), orig.get_size())
			t.path = "res://assets/sprites/%s/%d.png" % [a.sheet, fr]
		out.append(t)
	for i in sc.npcs.size():
		var e: Dictionary = sc.npcs[i]
		if e.sheet != "virtual" or not (m.EYE_ANIMS[int(e.frames[0])].has(0) or m.EYE_ANIMS[int(e.frames[0])].has(1)):
			continue
		var at: Vector2 = Vector2(e.x, e.y - (0 if e.blocker else 10)) + m.EYE_SHIFT.get("%s/%d" % [m.cur_key, i], Vector2.ZERO)
		var empty: bool = e.interactions.is_empty() and (e.get("free_dialogs") == null or e.free_dialogs.is_empty())
		out.append({label = "глазки %s" % e.get("name", "?"),  # пустая метка над объектом: годится любой объект
			expect = {kind = "any"} if empty else {kind = "npc", npc = e},
			at = Vector2(at.x * m.KX, at.y), draw = Rect2(-12, -7, 25, 16), flip = false,
			path = "res://assets/sprites/virtual.png", region = Rect2(0, 0, 0.2, 1.0)})  # кадр 0 из пяти
	return out


func image(path: String) -> Image:
	if not images.has(path):
		var im := Image.load_from_file(ProjectSettings.globalize_path(path))  # исходный PNG, не ресурс
		if im != null and im.is_compressed():
			im.decompress()
		images[path] = im
	return images[path]


func covers(t: Dictionary, s: Vector2) -> bool:  # s — экранная точка комнаты
	if t.has("poly"):
		return Geometry2D.is_point_in_polygon(s, t.poly)
	var l: Vector2 = s - t.at
	if t.flip:
		l.x = -l.x
	var uv: Vector2 = (l - t.draw.position) / t.draw.size
	if uv.x < 0 or uv.y < 0 or uv.x >= 1 or uv.y >= 1:
		return false
	var im := image(t.path)
	if im == null:
		return false
	var reg: Rect2 = t.get("region", Rect2(0, 0, 1, 1))
	uv = reg.position + uv * reg.size
	return im.get_pixel(int(uv.x * im.get_width()), int(uv.y * im.get_height())).a > 0.5


func visible_points(ts: Array, k: int) -> Array:  # точки цели k, где сверху не нарисовано ничего другого
	var t: Dictionary = ts[k]
	var pts := []
	var d: Rect2 = t.draw
	var y := d.position.y + STRIDE / 2
	while y < d.end.y:
		var x := d.position.x + STRIDE / 2
		while x < d.end.x:
			var s: Vector2 = t.at + Vector2(-x if t.flip else x, y) if not t.has("poly") else Vector2(x, y)
			if s.y < m.SCENE_H and covers(t, s) and not range(k + 1, ts.size()).any(func(j): return covers(ts[j], s)):
				pts.append(Vector2(s.x / m.KX, s.y))  # обратно в координаты комнаты, как у _hit
			x += STRIDE
		y += STRIDE
	return pts


func hits(t: Dictionary, h: Dictionary, strict := true) -> bool:
	var e: Dictionary = t.expect
	if e.kind == "any":
		return h.kind != "walk"
	if not strict and e.kind == "exit" and h.kind == "npc" and h.npc.blocker:
		return true  # проход заслонён (скелет у 1,1 до взрыва): тап по стрелке ведёт к заслону — так задумано
	if h.kind != e.kind:
		return false
	match e.kind:
		"item": return h.i == e.i
		"exit": return is_same(h.exit, e.exit)
		_: return is_same(h.npc, e.npc)


func describe(h: Dictionary) -> String:
	match h.kind:
		"item": return "предмет «%s»" % m.G.items[int(m.scenes[m.cur_key].floor_items[h.i].item)].name
		"exit": return "дверь → %d,%d" % [h.exit.to[0], h.exit.to[1]]
		"npc": return h.npc.get("name", "хотспот")
	return "ходьба"


func survey() -> void:  # прощупать всё видимое в комнате (каждое состояние комнаты — один раз)
	var ts := targets()
	var sc: Dictionary = m.scenes[m.cur_key]
	var state := "%d|%s|%s" % [sc.floor_items.size(), sc.exits.map(func(x): return m._exit_open(x)),
		sc.npcs.map(func(e): return [e.actor.frame() if e.has("actor") else -1, m._pending(e)])]
	for k in ts.size():
		var t: Dictionary = ts[k]
		var key := "%s|%s|%s" % [m.cur_key, t.label, state]
		if probes.has(key):
			continue
		var pr := {room = m.cur_key, what = t.label, points = 0, miss = 0, instead = {}, example = []}
		for p in visible_points(ts, k):
			pr.points += 1
			var h: Dictionary = m._hit(p)
			if not hits(t, h, false):
				pr.miss += 1
				var d := describe(h)
				pr.instead[d] = pr.instead.get(d, 0) + 1
				if pr.example.size() < 3:
					pr.example.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
		probes[key] = pr


func aim(expect: Dictionary, fallback: Vector2, what: String) -> void:
	# Тап в случайную видимую точку цели; если промахнулся — запомнить и тапнуть как раньше.
	survey()
	var ts := targets()
	var pts := []
	for k in ts.size():
		if hits({expect = expect}, ts[k].expect):
			pts = visible_points(ts, k)
			break
	if not pts.is_empty():
		var p: Vector2 = pts[rng.randi_range(0, pts.size() - 1)]
		if hits({expect = expect}, m._hit(p)):
			tap(p)
			return
		fallbacks.append("%s, %s: тап в видимую точку (%.1f, %.1f) ушёл в «%s»" % [m.cur_key, what, p.x, p.y, describe(m._hit(p))])
	tap(fallback)


func report() -> void:
	var worst := {}  # комната|цель -> худшее состояние
	for r in probes.values():
		var k: String = r.room + "|" + r.what
		if r.miss > 0 and (not worst.has(k) or float(r.miss) / r.points > float(worst[k].miss) / worst[k].points):
			worst[k] = r
	var rows := worst.values()
	rows.sort_custom(func(a, b): return float(a.miss) / a.points > float(b.miss) / b.points)
	var total := 0
	for r in probes.values():
		total += r.points
	print("TAPS %d:1080 — прощупано состояний целей %d, точек %d; целей с промахами %d, мимо при прохождении %d" \
		% [width, probes.size(), total, rows.size(), fallbacks.size()])
	for r in rows:
		var instead := ", ".join(r.instead.keys().map(func(k): return "%s ×%d" % [k, r.instead[k]]))
		print("  MISS %s %s: %d/%d (%d%%) → %s; напр. %s" % [r.room, r.what, r.miss, r.points,
			roundi(100.0 * r.miss / r.points), instead, r.example])
	for f in fallbacks:
		print("  FALLBACK " + f)
	for r in rows:  # мёртвая цель: нарисована, а тап по ней в основном просто идёт пешком
		check(r.instead.get("ходьба", 0) * 2 < r.points, "%s: «%s» не ловит тап — %d из %d видимых точек ведут в ходьбу" \
			% [r.room, r.what, r.instead.get("ходьба", 0), r.points])
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		file.store_string(JSON.stringify({width = width, probes = probes.values(), fallbacks = fallbacks}, "\t"))
