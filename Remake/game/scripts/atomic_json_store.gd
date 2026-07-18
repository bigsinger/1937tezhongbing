class_name AtomicJsonStore
extends RefCounted

## Small, dependency-free JSON persistence primitive.
##
## A replacement is written and verified in the destination directory before
## the previous primary is moved to `.bak`.  Therefore a process interruption
## leaves either the new primary or a recoverable backup.  A malformed primary
## is quarantined as `.corrupt` and never replaces a known-good backup.


static func save_document(
	path: String,
	document: Dictionary,
	validator: Callable = Callable(),
	keep_backup: bool = true,
) -> Dictionary:
	if path.is_empty():
		return _failure("empty_path", "persistence path is empty", ERR_INVALID_PARAMETER)
	if document.is_empty():
		return _failure("empty_document", "JSON document is empty", ERR_INVALID_DATA)
	if validator.is_valid() and not bool(validator.call(document)):
		return _failure(
			"validation_failed", "document failed validation before write", ERR_INVALID_DATA
		)

	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_path := absolute_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(directory_path)
	if directory_error != OK:
		return _failure(
			"directory_failed",
			"could not create persistence directory",
			directory_error,
		)

	var temporary_path := path + ".tmp"
	_remove_if_exists(temporary_path)
	var output := FileAccess.open(temporary_path, FileAccess.WRITE)
	if output == null:
		return _failure(
			"open_failed",
			"could not open temporary persistence file",
			FileAccess.get_open_error(),
		)
	output.store_string(JSON.stringify(document, "\t", true, true) + "\n")
	output.flush()
	output.close()

	var temporary_read := _read_single(temporary_path, validator)
	if not bool(temporary_read["ok"]):
		_remove_if_exists(temporary_path)
		return _failure(
			"verification_failed",
			"temporary persistence file did not verify: %s" % str(temporary_read["message"]),
			ERR_FILE_CORRUPT,
		)

	var backup_path := path + ".bak"
	var corrupt_path := path + ".corrupt"
	if FileAccess.file_exists(path):
		var current_read := _read_single(path, validator)
		if bool(current_read["ok"]):
			if keep_backup:
				_remove_if_exists(backup_path)
				var backup_error := _rename(path, backup_path)
				if backup_error != OK:
					_remove_if_exists(temporary_path)
					return _failure(
						"backup_failed",
						"could not move previous primary to backup",
						backup_error,
					)
			else:
				_remove_if_exists(path)
		else:
			# Invalid data must not displace a valid backup.  Keep one quarantine
			# file for diagnosis while making the primary name available.
			_remove_if_exists(corrupt_path)
			var quarantine_error := _rename(path, corrupt_path)
			if quarantine_error != OK:
				_remove_if_exists(temporary_path)
				return _failure(
					"quarantine_failed",
					"could not quarantine the invalid/old primary",
					quarantine_error,
				)

	var replace_error := _rename(temporary_path, path)
	if replace_error != OK:
		# Do not remove the verified temporary or backup here.  Either can be
		# used for manual recovery, and a later save safely replaces `.tmp`.
		return _failure(
			"replace_failed", "could not install verified primary", replace_error
		)
	return {
		"ok": true,
		"error": OK,
		"code": "ok",
		"message": "",
		"path": path,
		"backup_path": backup_path,
	}


static func load_document(
	path: String,
	validator: Callable = Callable(),
	fallback: Dictionary = {},
) -> Dictionary:
	if path.is_empty():
		return _load_failure(
			"empty_path", "persistence path is empty", fallback, "default"
		)

	var primary := _read_single(path, validator)
	if bool(primary["ok"]):
		return {
			"ok": true,
			"data": (primary["data"] as Dictionary).duplicate(true),
			"source": "primary",
			"recovered": false,
			"used_default": false,
			"code": "ok",
			"message": "",
			"path": path,
		}

	var backup_path := path + ".bak"
	var backup := _read_single(backup_path, validator)
	if bool(backup["ok"]):
		return {
			"ok": true,
			"data": (backup["data"] as Dictionary).duplicate(true),
			"source": "backup",
			"recovered": true,
			"used_default": false,
			"code": "backup_recovered",
			"message": "primary was unavailable; loaded backup",
			"path": backup_path,
			"primary_error": str(primary["message"]),
		}

	var primary_missing := str(primary["code"]) == "missing"
	var backup_missing := str(backup["code"]) == "missing"
	var code := "missing" if primary_missing and backup_missing else "unrecoverable"
	return _load_failure(
		code,
		"primary: %s; backup: %s" % [str(primary["message"]), str(backup["message"])],
		fallback,
		"default",
	)


static func _read_single(path: String, validator: Callable) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "code": "missing", "message": "file does not exist", "data": {}}
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		return {
			"ok": false,
			"code": "open_failed",
			"message": "file could not be opened (%d)" % FileAccess.get_open_error(),
			"data": {},
		}
	var text := input.get_as_text()
	input.close()
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		return {
			"ok": false,
			"code": "invalid_json",
			"message": "JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()],
			"data": {},
		}
	if not parser.data is Dictionary:
		return {
			"ok": false,
			"code": "invalid_root",
			"message": "JSON root is not an object",
			"data": {},
		}
	var data := parser.data as Dictionary
	if validator.is_valid() and not bool(validator.call(data)):
		return {
			"ok": false,
			"code": "validation_failed",
			"message": "JSON document failed validation",
			"data": {},
		}
	return {"ok": true, "code": "ok", "message": "", "data": data}


static func _rename(source_path: String, destination_path: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(source_path),
		ProjectSettings.globalize_path(destination_path),
	)


static func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _failure(code: String, message: String, error: Error) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"code": code,
		"message": message,
	}


static func _load_failure(
	code: String,
	message: String,
	fallback: Dictionary,
	source: String,
) -> Dictionary:
	return {
		"ok": false,
		"data": fallback.duplicate(true),
		"source": source,
		"recovered": false,
		"used_default": not fallback.is_empty(),
		"code": code,
		"message": message,
	}
