class_name OriginalStartupMediaQueue
extends RefCounted

## Deterministic state machine for the two blocking startup movies recovered
## from the original executable. Playback stays in MediaDirector; this class
## only owns ordering so missing conversions can be skipped without hanging.

var _entries: Array[Dictionary] = []
var _next_index := 0
var _awaiting_movie_id := ""
var _active := false


func begin(entries: Array[Dictionary]) -> void:
	_entries = entries.duplicate(true)
	_next_index = 0
	_awaiting_movie_id = ""
	_active = not _entries.is_empty()


func clear() -> void:
	_entries.clear()
	_next_index = 0
	_awaiting_movie_id = ""
	_active = false


func is_active() -> bool:
	return _active


func awaiting_movie_id() -> String:
	return _awaiting_movie_id


func next_movie_id() -> String:
	if not _active or not _awaiting_movie_id.is_empty():
		return ""
	while _next_index < _entries.size():
		var entry := _entries[_next_index]
		_next_index += 1
		var movie_id := str(entry.get("id", "")).strip_edges()
		if movie_id.is_empty():
			continue
		_awaiting_movie_id = movie_id
		return movie_id
	_active = false
	return ""


func resolve(movie_id: String) -> bool:
	if _awaiting_movie_id.is_empty() or movie_id != _awaiting_movie_id:
		return false
	_awaiting_movie_id = ""
	_active = _next_index < _entries.size()
	return true


func remaining_count() -> int:
	var remaining := maxi(_entries.size() - _next_index, 0)
	if not _awaiting_movie_id.is_empty():
		remaining += 1
	return remaining
