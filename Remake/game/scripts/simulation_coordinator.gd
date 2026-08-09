class_name SimulationCoordinator
extends RefCounted

signal command_scheduled(command: Dictionary)
signal command_executed(command: Dictionary)
signal tick_completed(tick: int)

const CLOCK_SCRIPT := preload("res://scripts/simulation_clock.gd")
const SYSTEM_SCRIPT := preload("res://scripts/simulation_system.gd")
const COMMAND_SCRIPT := preload("res://scripts/scheduled_game_command.gd")

const PHASE_COMMANDS := "commands"
const PHASE_WORLD := "world"
const PHASE_MOVEMENT := "movement"
const PHASE_PERCEPTION := "perception"
const PHASE_COMBAT := "combat"
const PHASE_MISSION_EVENTS := "mission_events"
const PHASE_MISSION_STATE := "mission_state"
const PHASE_PRESENTATION := "presentation"
const PHASE_ORDER: Array[String] = [
	PHASE_COMMANDS,
	PHASE_WORLD,
	PHASE_MOVEMENT,
	PHASE_PERCEPTION,
	PHASE_COMBAT,
	PHASE_MISSION_EVENTS,
	PHASE_MISSION_STATE,
	PHASE_PRESENTATION,
]
const MAX_COMMAND_LOG := 4096

var clock: SimulationClock = CLOCK_SCRIPT.new()
var _systems_by_phase: Dictionary = {}
var _command_handlers: Dictionary = {}
var _commands_by_tick: Dictionary = {}
var _command_sequence := 0
var _command_log: Array[Dictionary] = []
var _phase_usec: Dictionary = {}
var _system_usec: Dictionary = {}
var profiling_enabled := false


func _init() -> void:
	for phase: String in PHASE_ORDER:
		_systems_by_phase[phase] = []
		_phase_usec[phase] = 0


func register_system(
	system_id: String,
	phase: String,
	callback: Callable,
	priority: int = 0,
) -> bool:
	var normalized_phase := phase.strip_edges().to_lower()
	if normalized_phase not in PHASE_ORDER:
		return false
	unregister_system(system_id)
	var system: SimulationSystem = SYSTEM_SCRIPT.new(
		system_id,
		normalized_phase,
		priority,
		callback,
	)
	if not system.is_valid():
		return false
	var systems := _systems_by_phase[normalized_phase] as Array
	systems.append(system)
	systems.sort_custom(_system_precedes)
	return true


func unregister_system(system_id: String) -> bool:
	var normalized := system_id.strip_edges().to_lower()
	var removed := false
	for phase: String in PHASE_ORDER:
		var systems := _systems_by_phase[phase] as Array
		for index: int in range(systems.size() - 1, -1, -1):
			if (systems[index] as SimulationSystem).system_id == normalized:
				systems.remove_at(index)
				removed = true
	return removed


func register_command_handler(command_name: String, handler: Callable) -> bool:
	var normalized := COMMAND_SCRIPT.normalize_name(command_name)
	if normalized.is_empty() or not handler.is_valid():
		return false
	_command_handlers[normalized] = handler
	return true


func schedule_command(
	command_name: String,
	payload: Dictionary = {},
	source: String = "gameplay",
	actor_id: int = -1,
	delay_ticks: int = 1,
	precondition: Dictionary = {},
	timeout_ticks: int = -1,
	failure_policy: String = ScheduledGameCommand.FAILURE_SKIP,
) -> Dictionary:
	_command_sequence += 1
	var execute_tick := clock.tick + maxi(delay_ticks, 1)
	var timeout_tick := (
		execute_tick + timeout_ticks if timeout_ticks >= 0 else -1
	)
	var command: ScheduledGameCommand = COMMAND_SCRIPT.create(
		_command_sequence,
		execute_tick,
		command_name,
		payload,
		source,
		actor_id,
		precondition,
		timeout_tick,
		failure_policy,
	)
	if not command.is_valid():
		return {"accepted": false, "reason": "invalid_command"}
	var commands := _commands_by_tick.get(execute_tick, []) as Array
	commands.append(command)
	commands.sort_custom(_command_precedes)
	_commands_by_tick[execute_tick] = commands
	var document := command.to_dictionary()
	document["accepted"] = true
	command_scheduled.emit(document.duplicate(true))
	return document


func advance_time(delta_seconds: float) -> int:
	var previous_tick := clock.tick
	var count := clock.add_time(delta_seconds)
	for simulation_tick: int in range(previous_tick + 1, previous_tick + count + 1):
		_run_tick(simulation_tick)
	return count


func advance_exact_ticks(count: int = 1) -> int:
	if clock.paused or count <= 0:
		return 0
	var previous_tick := clock.tick
	clock.step_exact(count)
	for simulation_tick: int in range(previous_tick + 1, clock.tick + 1):
		_run_tick(simulation_tick)
	return count


func set_paused(value: bool) -> void:
	clock.set_paused(value)


func reset(new_tick: int = 0) -> void:
	clock.reset(new_tick)
	_commands_by_tick.clear()
	_command_log.clear()
	_command_sequence = 0
	for phase: String in PHASE_ORDER:
		_phase_usec[phase] = 0
	_system_usec.clear()


func set_profiling_enabled(enabled: bool) -> void:
	profiling_enabled = enabled
	_system_usec.clear()


func capture_state() -> Dictionary:
	var pending: Array[Dictionary] = []
	var ticks := _commands_by_tick.keys()
	ticks.sort()
	for raw_tick: Variant in ticks:
		for raw_command: Variant in _commands_by_tick[raw_tick] as Array:
			pending.append(
				(raw_command as ScheduledGameCommand).to_dictionary()
			)
	return {
		"schema_version": 1,
		"clock": clock.capture_state(),
		"command_sequence": _command_sequence,
		"pending_commands": pending,
	}


func restore_state(state: Dictionary) -> bool:
	if int(state.get("schema_version", 0)) != 1:
		return false
	var clock_state_value: Variant = state.get("clock", {})
	var pending_value: Variant = state.get("pending_commands", [])
	if not clock_state_value is Dictionary or not pending_value is Array:
		return false
	var restored_commands: Dictionary = {}
	var highest_sequence := maxi(0, int(state.get("command_sequence", 0)))
	for raw_value: Variant in pending_value as Array:
		if not raw_value is Dictionary:
			return false
		var command: ScheduledGameCommand = COMMAND_SCRIPT.from_dictionary(
			raw_value as Dictionary
		)
		if not command.is_valid():
			return false
		var commands := restored_commands.get(command.execute_tick, []) as Array
		commands.append(command)
		restored_commands[command.execute_tick] = commands
		highest_sequence = maxi(highest_sequence, command.sequence)
	if not clock.restore_state(clock_state_value as Dictionary):
		return false
	_commands_by_tick = restored_commands
	_command_sequence = highest_sequence
	_command_log.clear()
	return true


func command_log() -> Array[Dictionary]:
	return _command_log.duplicate(true)


func stats() -> Dictionary:
	var pending_count := 0
	for commands_value: Variant in _commands_by_tick.values():
		pending_count += (commands_value as Array).size()
	return {
		"tick": clock.tick,
		"tick_rate": SimulationClock.TICK_RATE,
		"paused": clock.paused,
		"pending_commands": pending_count,
		"command_sequence": _command_sequence,
		"command_log_count": _command_log.size(),
		"phase_usec": _phase_usec.duplicate(true),
		"system_usec": _system_usec.duplicate(true),
	}


func _run_tick(simulation_tick: int) -> void:
	if not profiling_enabled:
		# Production ticks do not pay for diagnostic attribution. The former path
		# sampled the clock twice and updated a String-keyed Dictionary for all
		# eight phases on every 60 Hz tick even though system profiling was off.
		# Dense missions consequently spent measurable frame budget profiling the
		# profiler. Diagnostic runs opt in through set_profiling_enabled().
		for phase: String in PHASE_ORDER:
			if phase == PHASE_COMMANDS:
				_execute_commands(simulation_tick)
			for raw_system: Variant in _systems_by_phase[phase] as Array:
				(raw_system as SimulationSystem).simulate_tick(
					simulation_tick,
					SimulationClock.FIXED_DELTA,
				)
		tick_completed.emit(simulation_tick)
		return
	for phase: String in PHASE_ORDER:
		var started_usec := Time.get_ticks_usec()
		if phase == PHASE_COMMANDS:
			_execute_commands(simulation_tick)
		for raw_system: Variant in _systems_by_phase[phase] as Array:
			var system := raw_system as SimulationSystem
			var system_started_usec := Time.get_ticks_usec()
			system.simulate_tick(
				simulation_tick,
				SimulationClock.FIXED_DELTA,
			)
			_system_usec[system.system_id] = int(
				_system_usec.get(system.system_id, 0)
			) + maxi(Time.get_ticks_usec() - system_started_usec, 0)
		_phase_usec[phase] = int(_phase_usec.get(phase, 0)) + maxi(
			Time.get_ticks_usec() - started_usec,
			0,
		)
	tick_completed.emit(simulation_tick)


func _execute_commands(simulation_tick: int) -> void:
	var commands_value: Variant = _commands_by_tick.get(simulation_tick)
	if not commands_value is Array:
		return
	_commands_by_tick.erase(simulation_tick)
	for raw_command: Variant in commands_value as Array:
		var command := raw_command as ScheduledGameCommand
		var document := command.to_dictionary()
		var result: Variant = false
		var handler_value: Variant = _command_handlers.get(command.name)
		if handler_value is Callable and (handler_value as Callable).is_valid():
			result = (handler_value as Callable).call(
				command.payload.duplicate(true),
				document.duplicate(true),
			)
		document["result"] = result
		document["completed_tick"] = simulation_tick
		_command_log.append(document)
		if _command_log.size() > MAX_COMMAND_LOG:
			_command_log.remove_at(0)
		command_executed.emit(document.duplicate(true))


static func _system_precedes(left: SimulationSystem, right: SimulationSystem) -> bool:
	if left.priority != right.priority:
		return left.priority > right.priority
	return left.system_id < right.system_id


static func _command_precedes(
	left: ScheduledGameCommand,
	right: ScheduledGameCommand,
) -> bool:
	return left.sequence < right.sequence
