class_name LocalizationService
extends RefCounted

const SUPPORTED_LOCALES: Array[String] = ["system", "zh_CN", "en"]
const CATALOG_PATHS := {
	"zh_CN": "res://data/localization/zh_CN.json",
	"en": "res://data/localization/en.json",
}

var installed_translations: Array[Translation] = []
var active_locale := "zh_CN"


func install(requested_locale: String = "system") -> String:
	for translation: Translation in installed_translations:
		TranslationServer.remove_translation(translation)
	installed_translations.clear()
	for locale: String in CATALOG_PATHS:
		var messages := _load_catalog(str(CATALOG_PATHS[locale]))
		if messages.is_empty():
			continue
		var translation := Translation.new()
		translation.locale = locale
		for key: String in messages:
			translation.add_message(StringName(key), str(messages[key]))
		TranslationServer.add_translation(translation)
		installed_translations.append(translation)
	active_locale = _resolve_locale(requested_locale)
	TranslationServer.set_locale(active_locale)
	return active_locale


func text(key: String, fallback: String = "") -> String:
	var translated := str(TranslationServer.translate(StringName(key)))
	if translated == key:
		return fallback if not fallback.is_empty() else key
	return translated


static func _resolve_locale(requested_locale: String) -> String:
	if requested_locale in ["zh_CN", "en"]:
		return requested_locale
	var system_locale := OS.get_locale().replace("-", "_")
	return "zh_CN" if system_locale.begins_with("zh") else "en"


static func _load_catalog(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	var result: Dictionary = {}
	for key: Variant in (parsed as Dictionary).keys():
		if key is String and (parsed as Dictionary)[key] is String:
			result[str(key)] = str((parsed as Dictionary)[key])
	return result
