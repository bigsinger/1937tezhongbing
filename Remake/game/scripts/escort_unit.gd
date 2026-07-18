class_name EscortUnit
extends "res://scripts/squad_unit.gd"

const FOLLOW_REPATH_SECONDS := 0.50
const FOLLOW_START_DISTANCE := 88.0
const FOLLOW_STOP_DISTANCE := 52.0

signal rescued(unit: Node2D, rescuer: Node2D)

var rescued_state := false
var follow_target: Node2D
var follow_repath_elapsed := FOLLOW_REPATH_SECONDS


func configure_escort(
	entity: Dictionary,
	texture: Texture2D,
	new_movement_groups: Array[Dictionary],
	new_idle_groups: Array[Dictionary],
	new_death_groups: Array[Dictionary],
	new_dynamic_occupancy: RefCounted,
) -> void:
	configure(
		str(entity.get("display_name", "escort")),
		Color("d3c27a"),
		Vector2(float(entity.get("x", 0)), float(entity.get("y", 0))),
		texture,
		new_movement_groups,
		new_idle_groups,
		int(entity.get("scene_index", -1)),
		new_dynamic_occupancy,
		Vector2(
			float(entity.get("reference_x", entity.get("x", 0))),
			float(entity.get("reference_y", entity.get("y", 0))),
		),
	)
	move_speed = 118.0
	configure_combat(
		2,
		maxi(int(entity.get("current_hit_points", 8)), 1),
		{},
		[],
		new_death_groups,
		false,
	)
	rescued_state = false
	follow_target = null
	follow_repath_elapsed = FOLLOW_REPATH_SECONDS
	queue_redraw()


func rescue(rescuer: Node2D) -> bool:
	if rescued_state or not is_alive or not _target_is_alive(rescuer):
		return false
	rescued_state = true
	faction_id = 3
	follow_target = rescuer
	follow_repath_elapsed = FOLLOW_REPATH_SECONDS
	rescued.emit(self, rescuer)
	queue_redraw()
	return true


func set_follow_target(target: Node2D) -> void:
	if _target_is_alive(target):
		follow_target = target


func _physics_process(delta: float) -> void:
	if is_alive and rescued_state and _target_is_alive(follow_target):
		follow_repath_elapsed += maxf(delta, 0.0)
		var distance := position.distance_to(follow_target.position)
		if distance <= FOLLOW_STOP_DISTANCE:
			if movement_path_index < movement_path.size():
				cancel_path()
		elif (
			distance >= FOLLOW_START_DISTANCE
			and follow_repath_elapsed >= FOLLOW_REPATH_SECONDS
		):
			follow_repath_elapsed = 0.0
			if dynamic_occupancy != null and dynamic_registered:
				var path: PackedVector2Array = dynamic_occupancy.find_path_for_scene(
					scene_index, position, follow_target.position
				)
				if not path.is_empty():
					issue_path(path)
	super._physics_process(delta)


func _draw() -> void:
	super._draw()
	if not rescued_state and is_alive:
		draw_arc(Vector2.ZERO, 27.0, 0.0, TAU, 32, Color(0.98, 0.82, 0.22), 2.5)
