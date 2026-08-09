class_name UiSafeAreaService
extends RefCounted

const REFERENCE_SIZE := Vector2(1920.0, 1080.0)
const MINIMUM_MARGIN := 12.0


func safe_rect(viewport_size: Vector2, ui_scale: float = 1.0) -> Rect2:
	var safe_size := Vector2(maxf(viewport_size.x, 1.0), maxf(viewport_size.y, 1.0))
	var scale := clampf(ui_scale, 0.75, 2.0)
	var margin := maxf(
		MINIMUM_MARGIN * scale,
		minf(safe_size.x, safe_size.y) * 0.018,
	)
	# Ultrawide and 4K displays keep controls in a readable central action-safe
	# area while the world remains visible to the edges.
	var content_width := minf(safe_size.x - margin * 2.0, REFERENCE_SIZE.x * scale)
	var content_height := minf(safe_size.y - margin * 2.0, REFERENCE_SIZE.y * scale)
	return Rect2(
		(safe_size - Vector2(content_width, content_height)) * 0.5,
		Vector2(content_width, content_height),
	)


func apply_to(control: Control, viewport_size: Vector2, ui_scale: float = 1.0) -> void:
	var rect := safe_rect(viewport_size, ui_scale)
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size
