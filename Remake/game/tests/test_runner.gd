extends SceneTree

const SIMULATION_SCRIPT: Script = preload("res://scripts/simulation.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var check_count: int = 0


func _init() -> void:
	var failures: Array[String] = []

	var moved: Vector2 = SIMULATION_SCRIPT.advance_towards(
		Vector2.ZERO, Vector2(3.0, 4.0), 2.0, 1.0
	)
	expect(moved.is_equal_approx(Vector2(1.2, 1.6)), "movement uses speed * delta", failures)

	var clamped: Vector2 = SIMULATION_SCRIPT.advance_towards(
		Vector2.ZERO, Vector2(3.0, 4.0), 20.0, 1.0
	)
	expect(clamped.is_equal_approx(Vector2(3.0, 4.0)), "movement does not overshoot", failures)
	expect(
		SIMULATION_SCRIPT.advance_towards(Vector2.ZERO, Vector2.ONE, -1.0, 1.0) == Vector2.ZERO,
		"negative speed is rejected",
		failures
	)
	expect(
		is_equal_approx(SIMULATION_SCRIPT.FIXED_DELTA, 1.0 / 60.0),
		"simulation tick is 60 Hz",
		failures
	)

	var offsets: Dictionary = {}
	var offset_sum := Vector2.ZERO
	var ordered_offsets: Array[Vector2] = []
	for index: int in range(5):
		var offset: Vector2 = SIMULATION_SCRIPT.formation_offset(index, 5)
		offsets[offset] = true
		offset_sum += offset
		ordered_offsets.append(offset)
	expect(offsets.size() == 5, "formation offsets are unique", failures)
	expect(offset_sum.is_zero_approx(), "formation centroid is centered", failures)

	var bounds := Rect2(Vector2(36.0, 100.0), Vector2(1208.0, 568.0))
	var corner_center: Vector2 = SIMULATION_SCRIPT.clamp_formation_center(
		Vector2.ZERO, ordered_offsets, bounds
	)
	var corner_targets: Dictionary = {}
	for offset: Vector2 in ordered_offsets:
		var target: Vector2 = corner_center + offset
		corner_targets[target] = true
		expect(point_is_inside(target, bounds), "formation target remains inside bounds", failures)
	expect(corner_targets.size() == 5, "corner formation targets stay unique", failures)

	var main = MAIN_SCENE.instantiate()
	main.create_interface()
	main.spawn_squad()
	expect(main.units.size() == 5, "prototype creates five squad members", failures)
	expect(main.selected_units.size() == 1, "prototype selects one member initially", failures)
	main.clear_selection()
	for unit in main.units:
		main.handle_selection(unit.position, true)
	expect(main.selected_units.size() == 5, "additive selection reaches all members", failures)
	main.issue_formation_move(Vector2.ZERO)
	var issued_targets: Dictionary = {}
	for unit in main.selected_units:
		issued_targets[unit.target_position] = true
		expect(
			point_is_inside(unit.target_position, bounds),
			"issued target remains inside bounds",
			failures
		)
	expect(issued_targets.size() == 5, "issued corner targets stay unique", failures)
	main.spawn_squad()
	expect(main.units.size() == 5, "reset restores five squad members", failures)
	expect(main.selected_units.size() == 1, "reset restores initial selection", failures)
	main.free()

	if failures.is_empty():
		print("Godot logic tests passed (%d checks)." % check_count)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func expect(value: bool, description: String, failures: Array[String]) -> void:
	check_count += 1
	if not value:
		failures.append(description)


func point_is_inside(point: Vector2, bounds: Rect2) -> bool:
	return (
		point.x >= bounds.position.x
		and point.y >= bounds.position.y
		and point.x <= bounds.end.x
		and point.y <= bounds.end.y
	)
