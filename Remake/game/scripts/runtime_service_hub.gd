class_name RuntimeServiceHub
extends RefCounted

const WORLD_SPATIAL_INDEX = preload("res://scripts/world_spatial_index.gd")
const PERCEPTION_SCHEDULER = preload("res://scripts/perception_scheduler.gd")
const RUNTIME_PERFORMANCE_MONITOR = preload(
	"res://scripts/runtime_performance_monitor.gd"
)
const CHECKPOINT_MANAGER = preload("res://scripts/checkpoint_manager.gd")
const RUNTIME_DIAGNOSTICS = preload("res://scripts/runtime_diagnostics.gd")
const GAME_COMMAND_BUS = preload("res://scripts/game_command_bus.gd")
const NAVIGATION_REQUEST_QUEUE = preload(
	"res://scripts/navigation_request_queue.gd"
)
const RUNTIME_SETTINGS_APPLIER = preload(
	"res://scripts/runtime_settings_applier.gd"
)
const APPLICATION_FOCUS_POLICY = preload(
	"res://scripts/application_focus_policy.gd"
)
const SIMULATION_COORDINATOR = preload(
	"res://scripts/simulation_coordinator.gd"
)
const MOVEMENT_RESERVATION_SERVICE = preload(
	"res://scripts/movement_reservation_service.gd"
)

var spatial_index: RefCounted
var perception_scheduler: RefCounted
var performance_monitor: RefCounted
var checkpoint_manager: RefCounted
var diagnostics: RefCounted
var command_bus: RefCounted
var navigation_requests: RefCounted
var settings_applier: RefCounted
var focus_policy: RefCounted
var simulation: RefCounted
var movement_reservations: RefCounted
var current_level_id := ""


func _init() -> void:
	spatial_index = WORLD_SPATIAL_INDEX.new()
	perception_scheduler = PERCEPTION_SCHEDULER.new()
	performance_monitor = RUNTIME_PERFORMANCE_MONITOR.new()
	checkpoint_manager = CHECKPOINT_MANAGER.new()
	diagnostics = RUNTIME_DIAGNOSTICS.new()
	command_bus = GAME_COMMAND_BUS.new()
	navigation_requests = NAVIGATION_REQUEST_QUEUE.new()
	settings_applier = RUNTIME_SETTINGS_APPLIER.new()
	focus_policy = APPLICATION_FOCUS_POLICY.new()
	simulation = SIMULATION_COORDINATOR.new()
	movement_reservations = MOVEMENT_RESERVATION_SERVICE.new()


func begin_level(level_id: String) -> void:
	current_level_id = level_id
	simulation.reset()
	movement_reservations.clear()
	spatial_index.clear()
	navigation_requests.cancel_all()
	performance_monitor.record_event("level_begin", 0, {"level_id": level_id})
	command_bus.emit_event("level_begin", {"level_id": level_id}, "lifecycle")


func stats() -> Dictionary:
	var empty_actor_indices: Array[int] = []
	return {
		"level_id": current_level_id,
		"spatial_index": spatial_index.stats(),
		"perception": perception_scheduler.schedule_snapshot(empty_actor_indices),
		"commands": command_bus.stats(),
		"navigation_requests": navigation_requests.stats(),
		"focus_policy": focus_policy.snapshot(),
		"simulation": simulation.stats(),
		"movement_reservations": movement_reservations.stats(),
	}


func build_diagnostics(runtime_settings: Dictionary) -> Dictionary:
	return diagnostics.build_document(
		current_level_id,
		runtime_settings,
		performance_monitor.snapshot(),
		stats(),
	)
