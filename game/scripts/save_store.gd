extends RefCounted
## Versioned, JSON-only saves. Restore references after rebuilding the original world.

const VERSION := 1
const AVATAR_COUNT := 10 # Original portrait frames assets/sprites/avatars/0..9.png.
const FIELDS := ["cur_key", "inv", "souls", "burn_msg", "ev", "ev_wait", "saved",
	"pending_pick", "drop_slot", "idle_time", "tick_acc", "ended", "follow_x", "dialog_lines"]
const NPC_FIELDS := ["x", "y", "extent", "radius", "flip", "blocker", "p", "frames", "free_dialogs"]
const ACTOR_FIELDS := ["x", "y", "flip", "anim", "next", "free", "f", "t"]


static func actor_state(actor) -> Dictionary:
	var data := {}
	for key in ACTOR_FIELDS:
		data[key] = actor.get(key)
	return data


static func capture(game) -> Dictionary:
	var data := {"version": VERSION, "rooms": {}, "devil": actor_state(game.devil)}
	for key in FIELDS:
		data[key] = game.get(key)
	for key in game.scenes:
		var room: Dictionary = game.scenes[key]
		var state := {"floor_items": room.floor_items.duplicate(true), "exits": [], "npcs": []}
		for ex in room.exits:
			state.exits.append(ex.open)
		for npc in room.npcs:
			var saved_npc := {"done": [], "then_free": [], "dialog_source": -1}
			for field in NPC_FIELDS:
				saved_npc[field] = npc[field]
			for i in npc.interactions.size():
				var interaction: Dictionary = npc.interactions[i]
				saved_npc.done.append(interaction.done)
				saved_npc.then_free.append(interaction.then_free_dialogs)
				if npc.free_dialogs != null and is_same(npc.free_dialogs, interaction.then_free_dialogs):
					saved_npc.dialog_source = i
			if npc.has("actor"):
				saved_npc.actor = actor_state(npc.actor)
			state.npcs.append(saved_npc)
		data.rooms[key] = state
	var target: Dictionary = game.target.duplicate()
	if target.has("npc"):
		target.ref = game.scenes[game.cur_key].npcs.find(target.npc)
		target.erase("npc")
	if target.has("exit"):
		target.ref = game.scenes[game.cur_key].exits.find(target.exit)
		target.erase("exit")
	data.target = target
	# Detach live dictionaries before returning the snapshot.
	return data.duplicate(true)


static func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value, lo: int, hi: int) -> bool:
	return _number(value) and value == int(value) and value >= lo and value <= hi


static func _actor_valid(value, anims: Array) -> bool:
	if not value is Dictionary or not value.has_all(ACTOR_FIELDS):
		return false
	if not _integer(value.anim, 0, anims.size() - 1) or not _integer(value.next, -1, anims.size() - 1):
		return false
	return _integer(value.f, 0, anims[int(value.anim)].size() - 1) and _number(value.t) \
		and value.t >= 0 and value.t < 1 and _number(value.x) and _number(value.y) \
		and value.flip is bool and value.free is bool


static func _lines_valid(lines, game) -> bool:
	if not lines is Array:
		return false
	for line in lines:
		if not line is Dictionary:
			return false
		if line.has("item"):
			if not _integer(line.item, 0, game.G.items.size() - 1):
				return false
		elif not line.has_all(["speaker", "avatar", "text"]) or not line.speaker is String \
			or not line.text is String or not _integer(line.avatar, 0, AVATAR_COUNT - 1):
			return false
	return true


static func _dialogs_valid(dialogs, game) -> bool:
	if dialogs == null:
		return true
	if not dialogs is Array:
		return false
	for dialog in dialogs:
		if not dialog is Dictionary or not dialog.has_all(["once", "lines"]) \
			or not dialog.once is bool or not dialog.get("used", false) is bool \
			or not _lines_valid(dialog.lines, game):
			return false
	return true


static func valid(data, game) -> bool:
	if not data is Dictionary or data.get("version") != VERSION or not data.has_all(FIELDS):
		return false
	if not data.cur_key is String or not game.G.scenes.has(data.cur_key) \
		or not data.get("rooms") is Dictionary or data.rooms.size() != game.G.scenes.size() \
		or not _actor_valid(data.get("devil"), game.SPR.devil.anims):
		return false
	if not data.inv is Array or data.inv.size() > game.INV_CAP or not data.souls is Dictionary:
		return false
	for item in data.inv:
		if not _integer(item, 0, game.G.items.size() - 1):
			return false
	for soul in data.souls:
		if soul not in ["d", "e", "f"] or data.souls[soul] != true:
			return false
	if not _integer(data.ev, -1, 27) or not _integer(data.ev_wait, 0, 1000) \
		or not _integer(data.burn_msg, 44, 46) or not data.ended is bool \
		or not _integer(data.drop_slot, -1, 1) or not _number(data.follow_x) \
		or not _number(data.idle_time) or not _number(data.tick_acc) \
		or not _lines_valid(data.dialog_lines, game) or not data.saved is Array:
		return false
	if data.saved.size() != 0 and data.saved.size() != 3:
		return false
	for value in data.saved:
		if not _number(value):
			return false
	if int(data.ev) in [2, 3] and data.saved.size() != 3:
		return false
	if data.saved.size() == 3 and not _integer(data.saved[0], 0, game.SPR.executioner.anims.size() - 1):
		return false
	for key in game.G.scenes:
		var original: Dictionary = game.G.scenes[key]
		var room = data.rooms.get(key)
		if not room is Dictionary or not room.get("floor_items") is Array \
			or not room.get("exits") is Array or room.exits.size() != original.exits.size() \
			or not room.get("npcs") is Array or room.npcs.size() != original.npcs.size():
			return false
		for item in room.floor_items:
			if not item is Dictionary or not _integer(item.get("item"), 0, game.G.items.size() - 1) \
				or not _integer(item.get("tx"), -1, 9) or not _integer(item.get("ty"), -1, 8):
				return false
		for open in room.exits:
			if not open is bool:
				return false
		for index in room.npcs.size():
			var npc = room.npcs[index]
			var orig: Dictionary = original.npcs[index]
			if not npc is Dictionary or not npc.has_all(NPC_FIELDS) or not npc.get("done") is Array \
				or npc.done.size() != orig.interactions.size() or not npc.get("then_free") is Array \
				or npc.then_free.size() != orig.interactions.size() \
				or not _integer(npc.get("dialog_source", -1), -1, orig.interactions.size() - 1):
				return false
			for field in ["x", "y", "extent", "radius"]:
				if not _number(npc[field]):
					return false
			if not npc.flip is bool or not npc.blocker is bool or not npc.frames is Array or npc.frames.is_empty() \
				or not _dialogs_valid(npc.free_dialogs, game) or not _integer(npc.p, 0, 10000):
				return false
			for done in npc.done:
				if not done is bool:
					return false
			for dialogs in npc.then_free:
				if not _dialogs_valid(dialogs, game):
					return false
			if game.SPR.has(orig.sheet):
				var anims: Array = game.SPR[orig.sheet].anims
				if not _actor_valid(npc.get("actor"), anims):
					return false
				for frame in npc.frames:
					if not _integer(frame, 0, anims.size() - 1):
						return false
	var current: Dictionary = data.rooms[data.cur_key]
	if not _integer(data.pending_pick, -2, current.floor_items.size() - 1):
		return false
	var target = data.get("target")
	if not target is Dictionary:
		return false
	if not target.is_empty():
		if target.get("kind") not in ["walk", "npc", "exit", "item", "drop"] or not _number(target.get("x")):
			return false
		match target.kind:
			"npc":
				if not _integer(target.get("ref"), 0, current.npcs.size() - 1): return false
			"exit":
				if not _integer(target.get("ref"), 0, current.exits.size() - 1) or not _number(target.get("then_x", -1)): return false
			"item":
				if not _integer(target.get("i"), 0, current.floor_items.size() - 1): return false
	return true


static func restore(data: Dictionary, game) -> void:
	game._reset_world()
	for field in FIELDS:
		game.set(field, data[field])
	game.inv = game.inv.map(func(item): return int(item))
	for field in ACTOR_FIELDS:
		game.devil.set(field, data.devil[field])
	for key in data.rooms:
		var room: Dictionary = game.scenes[key]
		var state: Dictionary = data.rooms[key]
		room.floor_items = state.floor_items
		for index in room.exits.size():
			room.exits[index].open = state.exits[index]
		for index in room.npcs.size():
			var npc: Dictionary = room.npcs[index]
			var saved_npc: Dictionary = state.npcs[index]
			for field in NPC_FIELDS:
				npc[field] = saved_npc[field]
			npc.p = int(npc.p)
			for i in npc.interactions.size():
				npc.interactions[i].done = saved_npc.done[i]
				npc.interactions[i].then_free_dialogs = saved_npc.then_free[i]
			if saved_npc.get("dialog_source", -1) >= 0:
				npc.free_dialogs = npc.interactions[int(saved_npc.dialog_source)].then_free_dialogs
			if npc.has("actor"):
				for field in ACTOR_FIELDS:
					npc.actor.set(field, saved_npc.actor[field])
	game.target = data.target.duplicate()
	if game.target.has("ref"):
		var field := "npc" if game.target.kind == "npc" else "exit"
		game.target[field] = game.scenes[game.cur_key]["npcs" if field == "npc" else "exits"][int(game.target.ref)]
		game.target.erase("ref")


static func _read_json(path: String):
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return parser.data


static func read(path: String, game) -> Dictionary:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var data = _read_json(candidate)
		if valid(data, game):
			return data
	return {}


static func write(path: String, game) -> Error:
	var data := capture(game)
	if not valid(data, game):
		return ERR_INVALID_DATA
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	if FileAccess.file_exists(path):
		var previous = _read_json(path)
		if valid(previous, game):
			error = DirAccess.copy_absolute(path, path + ".bak")
			if error != OK:
				return error
	return DirAccess.rename_absolute(path + ".tmp", path)
