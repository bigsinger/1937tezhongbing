class_name StealthFeedbackOverlay
extends Node2D

## Remembered coordinates are tactical guidance, not authoritative sensing.
## Five presentation updates per second are responsive while avoiding an
## unnecessary whole-enemy scan and CanvasItem redraw on every sixth frame.
const REFRESH_SECONDS := 0.20

var tracked_enemies: Array[Node2D] = []
var enabled := true
var elapsed := 0.0
var markers: Array[Dictionary] = []
var noise_preview: Dictionary = {}


func configure(enemies: Array, feedback_enabled: bool) -> void:
	# GDScript typed arrays are invariant: Array[EnemyUnit] cannot be passed to
	# an Array[Node2D] parameter even though every enemy is a Node2D. Keep the
	# public composition boundary untyped and validate once while copying.
	tracked_enemies.clear()
	for enemy_value: Variant in enemies:
		if (
			enemy_value is Node2D
			and (enemy_value as Node2D).has_method("tactical_feedback_memory_ticks")
		):
			tracked_enemies.append(enemy_value as Node2D)
	enabled = feedback_enabled
	if not enabled:
		markers.clear()
		noise_preview.clear()
	queue_redraw()


func set_noise_preview(center: Vector2, radius: float, visible: bool) -> void:
	noise_preview = (
		{"center": center, "radius": maxf(radius, 0.0)} if visible else {}
	)
	queue_redraw()


func _process(delta: float) -> void:
	if not enabled:
		return
	elapsed += maxf(delta, 0.0)
	if elapsed < REFRESH_SECONDS:
		return
	elapsed = fmod(elapsed, REFRESH_SECONDS)
	markers.clear()
	for enemy: Node2D in tracked_enemies:
		if enemy == null or not is_instance_valid(enemy) or not bool(enemy.get("is_alive")):
			continue
		var memory_ticks := int(enemy.call("tactical_feedback_memory_ticks"))
		if memory_ticks <= 0:
			continue
		var awareness := str(enemy.call("tactical_feedback_awareness_state"))
		if awareness in ["patrol", "classic"]:
			continue
		markers.append({
			"position": enemy.call("tactical_feedback_last_known_position"),
			"alpha": clampf(float(memory_ticks) / 300.0, 0.15, 0.65),
		})
	queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	for marker: Dictionary in markers:
		var position := marker.get("position", Vector2.ZERO) as Vector2
		var color := Color(1.0, 0.64, 0.18, float(marker.get("alpha", 0.4)))
		# Four short corners communicate a remembered coordinate without drawing
		# a selection circle beneath any living actor.
		draw_line(position + Vector2(-9, -5), position + Vector2(-4, -5), color, 1.0)
		draw_line(position + Vector2(-9, -5), position + Vector2(-9, 0), color, 1.0)
		draw_line(position + Vector2(9, 5), position + Vector2(4, 5), color, 1.0)
		draw_line(position + Vector2(9, 5), position + Vector2(9, 0), color, 1.0)
	if not noise_preview.is_empty():
		var center := noise_preview.get("center", Vector2.ZERO) as Vector2
		var radius := float(noise_preview.get("radius", 0.0))
		if radius > 0.0:
			var points := PackedVector2Array()
			for index: int in range(48):
				var angle := TAU * float(index) / 47.0
				points.append(center + Vector2(cos(angle), sin(angle) * 0.5) * radius)
			draw_polyline(points, Color(0.20, 0.82, 1.0, 0.46), 1.0, true)
