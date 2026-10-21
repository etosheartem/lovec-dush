extends SceneTree
## Прохождение на трёх душах по логике оригинала (без навигации — телепорт к цели).
## godot --headless --path game --script res://tests/walkthrough.gd

var m


var failed := false


func _initialize() -> void:
	start.call_deferred()


func start() -> void:
	m = load("res://main.tscn").instantiate()
	m.persistence_enabled = false
	m.save_path = "user://walkthrough_unused.json"
	m.settings_path = "user://walkthrough_settings_unused.cfg"
	root.add_child(m)
	m.new_game()
	run()
	# Freeze producers, then let the audio thread drain this accelerated run's play/stop queue.
	m.set_process(false)
	await create_timer(0.5).timeout
	m.sound.shutdown()
	await create_timer(0.5).timeout
	m.queue_free()
	await process_frame
	await process_frame
	quit(1 if failed else 0)


func check(condition: bool, message := "Проверка прохождения не выполнена") -> bool:
	if not condition:
		failed = true
		push_error(message)
	return condition


func run() -> void:
	settle()  # вступление + костёр
	if not check(m.cur_key == "3,2"):
		return

	take("1,0", 15); use("6,2", 3); use("6,2", 3)          # молот -> Дона Анна
	if not check(m.souls.has("e")):
		return
	use("1,0", 0)                                            # сера
	use("3,0", 0)                                            # бутыль для масла
	use("5,1", 0)                                            # масло у ключника
	use("3,0", 0); use("3,0", 0)                             # масло, сера -> динамит
	use("1,1", 0); use("0,1", 0)                             # взрыв -> Чернокнижник
	if not check(m.souls.has("d")):
		return
	take("2,0", 22); take("4,0", 10)
	use("4,2", 0); use("4,2", 0)                             # рыба, котелок с водой
	use("9,0", 1); use("9,0", 1)                             # рыба на блюде
	use("8,0", 0)
	take("8,0", 25); use("0,2", 0); use("8,0", 0)           # молоко -> сыр
	use("7,1", 0)                                            # мышь
	use("8,1", 1)
	take("0,1", 6); use("8,1", 1)                            # эликсир -> настоятель пропускает
	if not check(not m._npc("8,1", 1).blocker):
		return
	take("1,2", 31); use("9,1", 0)                           # деталь роботу
	take("6,1", 24); use("0,0", 1)                           # верёвка звонарю -> ключ на 12
	take("0,0", 28); use("9,1", 0)                           # робот
	use("9,1", 1)                                            # Послушник
	if not check(m.souls.size() == 3):
		return
	settle()                                                 # концовка оригинала -> ад
	if not check(m.cur_key == "0,3", "после трёх душ чёрт не попал в ад"):
		return
	take("1,3", 32); use("0,3", 1)                           # кочерга кочегару -> талон
	use("1,3", 0); use("1,3", 1)                             # талон секретарю, ковёр у Люцифера
	if not check(m.inv.has(34) and not m.ended, "после Люцифера не началась глава 2"):
		return
	# глава 2 «Недостача»: загадки с выбором ответа
	choose("2,3", 0, 2); choose("3,3", 0, 2); take("3,3", 36); take("3,3", 37)   # излишек ребра; кость между головами
	use("2,3", 0); choose("2,3", 1, 2)                          # перо -> командировочное; печать «для Его Темнейшества»
	use("4,3", 0); choose("4,3", 0, 2); use("5,3", 0)           # обол, «смотреть в оба» -> пара оболов, Харон
	if not check(m.cur_key == "0,4", "Харон не перевёз на Землю"):
		return
	use("2,4", 0); take("3,4", 40); use("6,4", 0)              # слеза ангела в сосуд; крыса шуту -> конец шутки
	choose("5,4", 0, 1); use("1,4", 0); use("4,4", 0); use("4,4", 0)   # шутка королю; мандрагора; два ингредиента
	use("2,4", 0); use("1,4", 0); use("3,4", 0); choose("2,4", 1, 2); use("2,4", 0)   # трезвый ангел, золото -> маска, нимб, полёт
	if not check(m.cur_key == "0,5", "ангел не долетел до рая"):
		return
	choose("0,5", 0, 1); take("2,5", 49); use("2,5", 0); choose("1,5", 0, 2)   # экзамен Петра; яблоко -> ключ; «ревизия»
	take("3,5", 51); choose("3,5", 0, 2); use("4,5", 0)          # чернильница; «перевернуть»; книга
	if not check(m.menus.page == "contract", "нет окна договора: %s" % m.menus.page):
		return
	m.finale_contract(false)
	settle()
	if not check(m.ended, "финал не запустился"):
		return
	if not failed:
		print("WALKTHROUGH OK")


func settle() -> void:
	for i in 600:
		if m.ended:
			return
		while m.dialog_lines.size() > 0:
			m._advance_dialog()
		m._process(0.05)
		if m.ev == -1 and m.devil.free and m.pending_pick == -2 and m.dialog_lines.is_empty():
			return
	if not check(false, "не успокоилось: ev=%d" % m.ev):
		return


func use(key: String, i: int) -> void:
	m.cur_key = key
	var e: Dictionary = m._npc(key, i)
	m.devil.x = e.x
	var before := done_count(e)
	m._interact(e)
	if not check(done_count(e) > before or m.ev != -1, "%s#%d (%s): ничего не сработало, инвентарь %s" % [key, i, e.name, m.inv]):
		return
	settle()


func choose(key: String, i: int, option: int) -> void:  # разговор с выбором: вопрос, затем ответ
	m.cur_key = key
	var e: Dictionary = m._npc(key, i)
	m.devil.x = e.x
	var before := done_count(e)
	m._interact(e)
	settle()
	if not check(m.menus.page == "choice", "%s#%d (%s): нет выбора ответа, в руках %s" % [key, i, e.name, m.inv]):
		return
	m.choose(option)
	settle()
	check(done_count(e) > before, "%s#%d (%s): верный ответ не засчитан" % [key, i, e.name])


func take(key: String, item: int) -> void:
	m.cur_key = key
	var fl: Array = m.scenes[key].floor_items
	var idx := -1
	for j in fl.size():
		if int(fl[j].item) == item:
			idx = j
	if not check(idx >= 0, "на %s нет предмета %d" % [key, item]):
		return
	m.pending_pick = idx
	m._do_pick()
	settle()
	if not check(m.inv.has(item)):
		return


func done_count(e: Dictionary) -> int:
	var n := 0
	for a in e.interactions:
		n += int(a.done)
	return n
