extends SceneTree
## Прохождение «как игрок»: только экранные тапы по стрелкам дверей, персонажам и предметам,
## ходьба пешком, путь между комнатами ищется по открытым дверям. Ловит то, что walkthrough.gd
## пропускает телепортом: перекрытые хитбоксы, недоходы до дверей, блокеры.
## godot --headless --path game --script res://tests/playthrough.gd

var m
var failed := false
var taps := 0


func _initialize() -> void:
	start.call_deferred()


func start() -> void:
	m = load("res://main.tscn").instantiate()
	m.persistence_enabled = false
	m.save_path = "user://playthrough_unused.json"
	m.settings_path = "user://playthrough_settings_unused.cfg"
	root.add_child(m)
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
				tap(m._arrow(ex)[0])
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
		tap(m._arrow(ex)[0])
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
	for it in fl:
		if int(it.item) == item:
			tap(Vector2(it.tx * 30 + 15, it.ty * 30 + 15))
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
	tap(center(m._npc_rect(e)))
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
	tap(center(m._npc_rect(e)))
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
	tap(center(m._npc_rect(e)))
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
