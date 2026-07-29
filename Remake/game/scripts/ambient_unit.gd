class_name AmbientUnit
extends "res://scripts/squad_unit.gd"

const IMPORTED_SPRITE_ANIMATION: Script = preload(
	"res://scripts/imported_sprite_animation.gd"
)
const WAYPOINT_HOLD_SECONDS := 0.15
const PATH_RETRY_SECONDS := 0.75

var patrol_waypoints := PackedVector2Array()
var patrol_index := 0
var patrol_enabled := false
var patrol_wait_remaining := 0.0
var patrol_path_in_flight := false
var path_request_delay_remaining := 0.0


func configure_ambient(
	entity: Dictionary,
	texture: Texture2D,
	new_movement_groups: Array[Dictionary],
	new_idle_groups: Array[Dictionary],
	new_death_groups: Array[Dictionary],
	new_dynamic_occupancy: RefCounted,
) -> void:
	var reference_position := Vector2(
		float(entity.get("reference_x", entity.get("x", 0))),
		float(entity.get("reference_y", entity.get("y", 0))),
	)
	configure(
		str(entity.get("display_name", "ambient")),
		Color("c6b98a"),
		reference_position,
		texture,
		new_movement_groups,
		new_idle_groups,
		int(entity.get("scene_index", -1)),
		new_dynamic_occupancy,
		reference_position,
	)
	configure_runtime_actor_type(entity)
	var header_values: Variant = entity.get("database_header_values", [])
	var authored_speed := 36.0
	if header_values is Array and (header_values as Array).size() > 4:
		authored_speed = maxf(float((header_values as Array)[4]), 1.0)
	move_speed = authored_speed
	configure_combat(
		int(entity.get("faction_id", entity.get("team_id", 2))),
		maxi(int(entity.get("current_hit_points", 8)), 1),
		{},
		[],
		new_death_groups,
		false,
	)
	var direction_index := clampi(int(entity.get("direction_index", 1)), 1, 8)
	set_animation_group(
		IMPORTED_SPRITE_ANIMATION.legacy_group_index_for_direction(direction_index)
	)
	apply_idle_frame()
	patrol_waypoints = _patrol_world_points(entity.get("patrol_waypoints", []))
	patrol_index = clampi(
		int(entity.get("patrol_current_waypoint_index", 0)),
		0,
		maxi(patrol_waypoints.size() - 1, 0),
	)
	patrol_enabled = (
		bool(entity.get("patrol_enabled", true))
		and not patrol_waypoints.is_empty()
	)
	patrol_wait_remaining = 0.0
	patrol_path_in_flight = false
	path_request_delay_remaining = float(posmod(scene_index * 19, 12)) / 60.0
	queue_redraw()


func _physics_process(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	path_request_delay_remaining = maxf(
		path_request_delay_remaining - safe_delta,
		0.0,
	)
	if is_alive and combat_action == CombatAction.NONE and hurt_remaining <= 0.0:
		_update_patrol(safe_delta)
	super._physics_process(safe_delta)


func _update_patrol(delta: float) -> void:
	if (
		not patrol_enabled
		or patrol_waypoints.is_empty()
		or path_request_delay_remaining > 0.0
		or movement_path_index < movement_path.size()
	):
		return
	if patrol_path_in_flight:
		patrol_path_in_flight = false
		patrol_wait_remaining = WAYPOINT_HOLD_SECONDS
		apply_idle_frame()
		return
	if patrol_wait_remaining > 0.0:
		patrol_wait_remaining = maxf(patrol_wait_remaining - delta, 0.0)
		return
	var next_index := _next_unreached_patrol_index()
	if next_index < 0:
		path_request_delay_remaining = PATH_RETRY_SECONDS
		return
	patrol_index = next_index
	var path := PackedVector2Array()
	if dynamic_occupancy != null and scene_index >= 0:
		path = dynamic_occupancy.find_path_for_scene(
			scene_index,
			position,
			patrol_waypoints[patrol_index],
		)
	if path.is_empty():
		path_request_delay_remaining = PATH_RETRY_SECONDS
		return
	issue_path(path)
	patrol_path_in_flight = true


func _next_unreached_patrol_index() -> int:
	if patrol_waypoints.is_empty():
		return -1
	var candidate_index := clampi(
		patrol_index,
		0,
		patrol_waypoints.size() - 1,
	)
	for unused_waypoint in range(patrol_waypoints.size()):
		if position.distance_squared_to(patrol_waypoints[candidate_index]) > 4.0:
			return candidate_index
		candidate_index = (candidate_index + 1) % patrol_waypoints.size()
	return -1


static func _patrol_world_points(raw_waypoints: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not raw_waypoints is Array:
		return result
	for raw_waypoint: Variant in raw_waypoints as Array:
		if not raw_waypoint is Dictionary:
			continue
		var waypoint := raw_waypoint as Dictionary
		result.append(
			Vector2(
				float(int(waypoint.get("x", 0)) * 32 + 16),
				float(int(waypoint.get("y", 0)) * 16 + 8),
			)
		)
	return result
