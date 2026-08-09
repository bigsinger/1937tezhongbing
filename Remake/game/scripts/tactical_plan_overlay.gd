class_name TacticalPlanOverlay
extends Node2D

var entries: Array[Dictionary] = []


func set_entries(value: Array[Dictionary]) -> void:
	entries = value.duplicate(true)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var by_actor: Dictionary = {}
	for entry: Dictionary in entries:
		var actor_id := int(entry.get("actor_id", -1))
		var queue := by_actor.get(actor_id, []) as Array
		queue.append(entry)
		by_actor[actor_id] = queue
	for raw_actor: Variant in by_actor.keys():
		var queue := by_actor[raw_actor] as Array
		var previous := Vector2.ZERO
		var has_previous := false
		for index: int in range(queue.size()):
			var entry := queue[index] as Dictionary
			var screen_position := entry.get("screen_position", Vector2.ZERO) as Vector2
			var risk := clampf(float(entry.get("risk", 0.0)), 0.0, 1.0)
			var valid := bool(entry.get("valid", true))
			var route_color := (
				Color(0.88, 0.26, 0.26, 0.96)
				if not valid
				else
				Color(0.95, 0.28, 0.18, 0.96)
				if risk >= 0.8
				else Color(0.98, 0.70, 0.18, 0.94)
				if risk > 0.0
				else Color(0.30, 0.88, 0.78, 0.92)
			)
			if has_previous:
				draw_dashed_line(previous, screen_position, route_color, 1.5, 7.0)
			draw_rect(Rect2(screen_position - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), Color(0.04, 0.09, 0.08, 0.95), true)
			draw_rect(Rect2(screen_position - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), Color(0.30, 0.88, 0.78, 1.0), false, 1.0)
			draw_string(font, screen_position + Vector2(8.0, 5.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
			var detail := str(entry.get("detail", ""))
			if not detail.is_empty():
				draw_string(
					font,
					screen_position + Vector2(8.0, 20.0),
					detail,
					HORIZONTAL_ALIGNMENT_LEFT,
					180.0,
					11,
					Color(1.0, 0.84, 0.66, 0.96) if valid else Color(1.0, 0.55, 0.55, 0.98),
				)
			previous = screen_position
			has_previous = true
