extends Node
## Quality changes rendering features (effects, antialiasing), never the logical canvas size.
## Один набор картинок (2К, WebP) на все режимы — APK вдвое меньше.

signal changed

const DEFAULT_PRESET := "maximum"
const PROFILES := {
	"maximum": {
		"label": "Максимальное", "texture_root": "res://assets/hd",
		"effects_level": 2, "msaa_2d": Viewport.MSAA_4X,
	},
	"high": {
		"label": "Высокое", "texture_root": "res://assets/hd",
		"effects_level": 1, "msaa_2d": Viewport.MSAA_2X,
	},
	"economy": {
		"label": "Экономное", "texture_root": "res://assets/hd",
		"effects_level": 0, "msaa_2d": Viewport.MSAA_DISABLED,
	},
}

var settings_path := "user://settings.cfg"
var _preset := DEFAULT_PRESET
var preset: String:
	get: return _preset
var label: String:
	get: return PROFILES[_preset].label
var texture_root: String:
	get: return PROFILES[_preset].texture_root
var effects_level: int:
	get: return PROFILES[_preset].effects_level
var msaa_2d: int:
	get: return PROFILES[_preset].msaa_2d
var texture_filter: int:
	get: return CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _ready() -> void:
	load_settings()


func load_settings() -> bool:
	var config := ConfigFile.new()
	var result := config.load(settings_path)
	var stored = config.get_value("graphics", "preset", DEFAULT_PRESET) if result == OK else DEFAULT_PRESET
	var valid: bool = stored is String and PROFILES.has(stored)
	set_preset(stored if valid else DEFAULT_PRESET, false)
	return valid and result in [OK, ERR_FILE_NOT_FOUND]


func set_preset(preset_id: String, persist := true) -> bool:
	if not PROFILES.has(preset_id):
		return false
	# Keep the previous active profile if settings could not be written.
	if persist and not _save_preset(preset_id):
		return false
	if _preset != preset_id:
		_preset = preset_id
		changed.emit()
	return true


func save_settings() -> bool:
	return _save_preset(_preset)


func _save_preset(preset_id: String) -> bool:
	var config := ConfigFile.new()
	var result := config.load(settings_path)
	if result not in [OK, ERR_FILE_NOT_FOUND]:
		return false
	config.set_value("graphics", "preset", preset_id)
	return config.save(settings_path) == OK


func apply_viewport(viewport: Viewport) -> void:
	if viewport == null:
		return
	viewport.msaa_2d = msaa_2d
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
