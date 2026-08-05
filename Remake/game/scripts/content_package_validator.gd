class_name ContentPackageValidator
extends RefCounted

const SUPPORTED_SCHEMA := 1


static func validate(
	manifest_path: String,
	content_root: String,
	expected_profile: String = "",
	allow_missing_manifest: bool = false,
) -> Dictionary:
	var result := {
		"ok": false,
		"status": "invalid",
		"profile_id": "",
		"content_identity_sha256": "",
		"checked_critical_files": 0,
		"failures": [],
	}
	if not FileAccess.file_exists(manifest_path):
		if allow_missing_manifest:
			result["ok"] = true
			result["status"] = "development_unmanifested"
			return result
		(result["failures"] as Array).append("content manifest is missing")
		return result
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(manifest_path)
	)
	if not parsed is Dictionary:
		(result["failures"] as Array).append("content manifest is not valid JSON")
		return result
	var document := parsed as Dictionary
	if int(document.get("schema_version", 0)) != SUPPORTED_SCHEMA:
		(result["failures"] as Array).append("unsupported content manifest schema")
		return result
	var profile_id := str(document.get("profile_id", ""))
	result["profile_id"] = profile_id
	result["content_identity_sha256"] = str(
		document.get("content_identity_sha256", "")
	)
	if not expected_profile.is_empty() and profile_id != expected_profile:
		(result["failures"] as Array).append(
			"content profile mismatch: expected %s, found %s"
			% [expected_profile, profile_id]
		)
	var normalized_root := content_root.simplify_path().trim_suffix("/")
	var root_prefix := normalized_root + "/"
	var entries_value: Variant = document.get("files", [])
	if not entries_value is Array:
		(result["failures"] as Array).append("content manifest file list is invalid")
		return result
	for entry_value: Variant in entries_value as Array:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		if not bool(entry.get("critical", false)):
			continue
		result["checked_critical_files"] = (
			int(result["checked_critical_files"]) + 1
		)
		var relative_path := str(entry.get("path", "")).replace("\\", "/")
		var candidate := root_prefix.path_join(relative_path).simplify_path()
		if not candidate.begins_with(root_prefix):
			(result["failures"] as Array).append(
				"unsafe content path: %s" % relative_path
			)
			continue
		if not FileAccess.file_exists(candidate):
			(result["failures"] as Array).append(
				"critical content is missing: %s" % relative_path
			)
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			(result["failures"] as Array).append(
				"critical content cannot be opened: %s" % relative_path
			)
			continue
		var observed_length := file.get_length()
		file.close()
		if observed_length != int(entry.get("bytes", -1)):
			(result["failures"] as Array).append(
				"critical content length mismatch: %s" % relative_path
			)
			continue
		var expected_hash := str(entry.get("sha256", "")).to_lower()
		if (
			not expected_hash.is_empty()
			and FileAccess.get_sha256(candidate).to_lower() != expected_hash
		):
			(result["failures"] as Array).append(
				"critical content hash mismatch: %s" % relative_path
			)
	result["ok"] = (result["failures"] as Array).is_empty()
	result["status"] = "passed" if bool(result["ok"]) else "invalid"
	return result
