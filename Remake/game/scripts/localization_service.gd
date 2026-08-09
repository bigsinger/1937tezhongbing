class_name LocalizationService
extends RefCounted

const SUPPORTED_LOCALES: Array[String] = ["system", "zh_CN", "en"]
const CATALOG_PATHS := {
	"zh_CN": "res://data/localization/zh_CN.json",
	"en": "res://data/localization/en.json",
}

var installed_translations: Array[Translation] = []
var active_locale := "zh_CN"
var diagnostics: Array[String] = []
var catalogs: Dictionary = {}

static var _standalone_catalogs: Dictionary = {}


func install(requested_locale: String = "system") -> String:
	diagnostics.clear()
	catalogs.clear()
	for translation: Translation in installed_translations:
		TranslationServer.remove_translation(translation)
	installed_translations.clear()
	var chinese := _load_catalog(str(CATALOG_PATHS["zh_CN"]))
	var english := _load_catalog(str(CATALOG_PATHS["en"]))
	if chinese.is_empty():
		diagnostics.append("Simplified-Chinese localization catalog is missing or invalid.")
	var english_merged := chinese.duplicate(true)
	for key: String in english:
		if chinese.has(key) and _placeholder_signature(str(chinese[key])) != _placeholder_signature(str(english[key])):
			diagnostics.append("Placeholder mismatch for %s; using zh_CN fallback." % key)
			continue
		english_merged[key] = english[key]
	for key: String in chinese:
		if not english.has(key):
			diagnostics.append("Missing en translation for %s; using zh_CN fallback." % key)
	catalogs = {"zh_CN": chinese, "en": english_merged}
	for locale: String in ["zh_CN", "en"]:
		var messages := catalogs.get(locale, {}) as Dictionary
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


static func translate_key(key: String, fallback_locale: String = "zh_CN") -> String:
	if key.is_empty():
		return ""
	var translated := str(TranslationServer.translate(StringName(key)))
	if not translated.is_empty() and translated != key:
		return translated
	var locale := fallback_locale if fallback_locale in ["zh_CN", "en"] else "zh_CN"
	if not _standalone_catalogs.has(locale):
		_standalone_catalogs[locale] = _load_catalog(str(CATALOG_PATHS[locale]))
	var catalog := _standalone_catalogs.get(locale, {}) as Dictionary
	if catalog.has(key):
		return str(catalog[key])
	if locale != "zh_CN":
		if not _standalone_catalogs.has("zh_CN"):
			_standalone_catalogs["zh_CN"] = _load_catalog(
				str(CATALOG_PATHS["zh_CN"])
			)
		var chinese := _standalone_catalogs.get("zh_CN", {}) as Dictionary
		if chinese.has(key):
			return str(chinese[key])
	return key


func validation_snapshot() -> Dictionary:
	var chinese := catalogs.get("zh_CN", {}) as Dictionary
	var english := catalogs.get("en", {}) as Dictionary
	return {
		"ok": not chinese.is_empty() and chinese.size() == english.size(),
		"zh_CN_count": chinese.size(),
		"en_count": english.size(),
		"diagnostics": diagnostics.duplicate(),
	}


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


static func _placeholder_signature(value: String) -> Array[String]:
	var signature: Array[String] = []
	var expression := RegEx.new()
	if expression.compile("%(?:[0-9]+\\$)?[-+0 #]*(?:[0-9]+|\\*)?(?:\\.(?:[0-9]+|\\*))?[diouxXeEfFgGsc]") != OK:
		return signature
	for match_value: RegExMatch in expression.search_all(value.replace("%%", "")):
		var placeholder := match_value.get_string()
		var type_character := placeholder.right(1)
		signature.append(type_character.to_lower())
	return signature
