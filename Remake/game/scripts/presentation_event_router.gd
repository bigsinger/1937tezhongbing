class_name PresentationEventRouter
extends RefCounted

signal status_requested(message: String)
signal caption_requested(message: String, duration_seconds: float)
signal audio_requested(event: Dictionary)

var last_status := ""
var status_serial := 0


func status(message: String) -> void:
	if message.is_empty():
		return
	last_status = message
	status_serial += 1
	status_requested.emit(message)


func caption(message: String, duration_seconds: float = 2.4) -> void:
	if not message.is_empty():
		caption_requested.emit(message, maxf(duration_seconds, 0.1))


func audio(event: Dictionary) -> void:
	if not event.is_empty():
		audio_requested.emit(event.duplicate(true))


func snapshot() -> Dictionary:
	return {"last_status": last_status, "status_serial": status_serial}
