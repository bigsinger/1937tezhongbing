class_name LegacyAmbientParticleField
extends Control

## M1937 sub_45FCB0 constructs one active field with 150 primary particles,
## 20 secondary particles and a maximum primary size of 17. sub_45FF20 is
## reached only while the original mission selector is 3 or 6.
const ACTIVE_LEVEL_IDS := ["m002", "m005"]
const PRIMARY_COUNT := 150
const SECONDARY_COUNT := 20
const PRIMARY_MAX_SIZE := 17
const LOGICAL_SIZE := Vector2(1024.0, 768.0)
const WIND_ANGLE_DEGREES := 80.0
const WIND_DIRECTION := Vector2(
	0.17364817766693041,
	0.984807753012208,
)

var random_source: Node
var level_id := ""
var primary_positions := PackedVector2Array()
var primary_alphas := PackedInt32Array()
var primary_lifetimes := PackedInt32Array()
var primary_speeds := PackedInt32Array()
var primary_sizes := PackedInt32Array()
var secondary_positions := PackedVector2Array()
var secondary_alphas := PackedInt32Array()
var secondary_lifetimes := PackedInt32Array()
var tick_counter := 0
var weather_phase := 0
var weather_phase_increasing := true
var stored_width := 0
var stored_height := 0
var flash_active := false
var flash_frame := 0
var update_serial := 0
var random_failure := false
var random_batch_active := false
var random_batch_state_before := 1
var random_batch_state := 1
var random_batch_call_sites := PackedInt32Array()
var random_batch_draw_count := 0
var random_batch_trace_enabled := false
var primary_multimesh_instance: MultiMeshInstance2D
var secondary_multimesh_instance: MultiMeshInstance2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_physics_priority = 3_000_000
	_create_particle_multimeshes()
	resized.connect(_update_particle_multimeshes)


func configure(source: Node, new_level_id: String) -> bool:
	random_source = source
	level_id = new_level_id
	primary_positions = PackedVector2Array()
	primary_positions.resize(PRIMARY_COUNT)
	primary_alphas = PackedInt32Array()
	primary_alphas.resize(PRIMARY_COUNT)
	primary_lifetimes = PackedInt32Array()
	primary_lifetimes.resize(PRIMARY_COUNT)
	primary_speeds = PackedInt32Array()
	primary_speeds.resize(PRIMARY_COUNT)
	primary_sizes = PackedInt32Array()
	primary_sizes.resize(PRIMARY_COUNT)
	primary_sizes.fill(8)
	secondary_positions = PackedVector2Array()
	secondary_positions.resize(SECONDARY_COUNT)
	secondary_alphas = PackedInt32Array()
	secondary_alphas.resize(SECONDARY_COUNT)
	secondary_lifetimes = PackedInt32Array()
	secondary_lifetimes.resize(SECONDARY_COUNT)
	tick_counter = 0
	weather_phase = 0
	weather_phase_increasing = true
	stored_width = 0
	stored_height = 0
	flash_active = false
	flash_frame = 0
	update_serial = 0
	random_failure = false
	random_batch_active = false
	random_batch_state_before = 1
	random_batch_state = 1
	random_batch_call_sites = PackedInt32Array()
	random_batch_draw_count = 0
	random_batch_trace_enabled = false
	visible = ACTIVE_LEVEL_IDS.has(level_id)
	set_physics_process(visible)
	_update_particle_multimeshes()
	queue_redraw()
	return visible


func runtime_snapshot() -> Dictionary:
	var primary_particles: Array[Dictionary] = []
	for index: int in range(PRIMARY_COUNT):
		primary_particles.append({
			"position": primary_positions[index],
			"alpha": primary_alphas[index],
			"lifetime": primary_lifetimes[index],
			"speed": primary_speeds[index],
			"size": primary_sizes[index],
		})
	var secondary_particles: Array[Dictionary] = []
	for index: int in range(SECONDARY_COUNT):
		secondary_particles.append({
			"position": secondary_positions[index],
			"alpha": secondary_alphas[index],
			"lifetime": secondary_lifetimes[index],
		})
	return {
		"level_id": level_id,
		"tick_counter": tick_counter,
		"weather_phase": weather_phase,
		"weather_phase_increasing": weather_phase_increasing,
		"stored_width": stored_width,
		"stored_height": stored_height,
		"flash_active": flash_active,
		"flash_frame": flash_frame,
		"update_serial": update_serial,
		"primary_particles": primary_particles,
		"secondary_particles": secondary_particles,
	}


func restore_runtime_snapshot(state: Dictionary) -> bool:
	if (
		state.is_empty()
		or str(state.get("level_id", level_id)) != level_id
		or not ACTIVE_LEVEL_IDS.has(level_id)
	):
		return false
	var primary_value: Variant = state.get("primary_particles", [])
	var secondary_value: Variant = state.get("secondary_particles", [])
	if (
		not primary_value is Array
		or not secondary_value is Array
		or (primary_value as Array).size() != PRIMARY_COUNT
		or (secondary_value as Array).size() != SECONDARY_COUNT
	):
		return false
	primary_positions = PackedVector2Array()
	primary_positions.resize(PRIMARY_COUNT)
	primary_alphas = PackedInt32Array()
	primary_alphas.resize(PRIMARY_COUNT)
	primary_lifetimes = PackedInt32Array()
	primary_lifetimes.resize(PRIMARY_COUNT)
	primary_speeds = PackedInt32Array()
	primary_speeds.resize(PRIMARY_COUNT)
	primary_sizes = PackedInt32Array()
	primary_sizes.resize(PRIMARY_COUNT)
	for index: int in range(PRIMARY_COUNT):
		var value: Variant = (primary_value as Array)[index]
		if not value is Dictionary:
			return false
		var primary_particle := _restore_particle(
			value as Dictionary,
			true,
		)
		if primary_particle.is_empty():
			return false
		primary_positions[index] = (
			primary_particle.get("position", Vector2.ZERO) as Vector2
		)
		primary_alphas[index] = int(primary_particle.get("alpha", 0))
		primary_lifetimes[index] = int(
			primary_particle.get("lifetime", 0)
		)
		primary_speeds[index] = int(primary_particle.get("speed", 0))
		primary_sizes[index] = int(primary_particle.get("size", 8))
	secondary_positions = PackedVector2Array()
	secondary_positions.resize(SECONDARY_COUNT)
	secondary_alphas = PackedInt32Array()
	secondary_alphas.resize(SECONDARY_COUNT)
	secondary_lifetimes = PackedInt32Array()
	secondary_lifetimes.resize(SECONDARY_COUNT)
	for index: int in range(SECONDARY_COUNT):
		var value: Variant = (secondary_value as Array)[index]
		if not value is Dictionary:
			return false
		var secondary_particle := _restore_particle(
			value as Dictionary,
			false,
		)
		if secondary_particle.is_empty():
			return false
		secondary_positions[index] = (
			secondary_particle.get(
				"position",
				Vector2.ZERO,
			) as Vector2
		)
		secondary_alphas[index] = int(
			secondary_particle.get("alpha", 0)
		)
		secondary_lifetimes[index] = int(
			secondary_particle.get("lifetime", 0)
		)
	tick_counter = maxi(int(state.get("tick_counter", 0)), 0)
	weather_phase = clampi(int(state.get("weather_phase", 0)), 0, 8)
	weather_phase_increasing = bool(
		state.get("weather_phase_increasing", true)
	)
	stored_width = maxi(int(state.get("stored_width", 0)), 0)
	stored_height = maxi(int(state.get("stored_height", 0)), 0)
	flash_active = bool(state.get("flash_active", false))
	flash_frame = clampi(int(state.get("flash_frame", 0)), 0, 6)
	update_serial = maxi(int(state.get("update_serial", 0)), 0)
	random_failure = false
	random_batch_active = false
	random_batch_call_sites = PackedInt32Array()
	random_batch_draw_count = 0
	random_batch_trace_enabled = false
	_update_particle_multimeshes()
	queue_redraw()
	return true


static func _restore_particle(
	value: Dictionary,
	primary: bool,
) -> Dictionary:
	var position_value: Variant = value.get(
		"position",
		Vector2.ZERO,
	)
	var restored_position := Vector2.ZERO
	if position_value is Vector2:
		restored_position = position_value as Vector2
	elif position_value is Dictionary:
		var position_dictionary := position_value as Dictionary
		restored_position = Vector2(
			float(position_dictionary.get("x", 0.0)),
			float(position_dictionary.get("y", 0.0)),
		)
	else:
		return {}
	var particle := {
		"position": restored_position,
		"alpha": clampi(int(value.get("alpha", 0)), 0, 255),
		"lifetime": int(value.get("lifetime", 0)),
	}
	if primary:
		particle["speed"] = maxi(int(value.get("speed", 0)), 0)
		particle["size"] = clampi(
			int(value.get("size", 8)),
			8,
			PRIMARY_MAX_SIZE,
		)
	return particle


func _physics_process(_delta: float) -> void:
	if (
		random_failure
		or random_source == null
		or not is_instance_valid(random_source)
	):
		return
	if not _advance_original_update():
		random_failure = true
		push_error(
			"Original ambient-particle random stream failed for %s"
			% level_id
		)
		return
	update_serial += 1
	_update_particle_multimeshes()
	queue_redraw()


func _advance_original_update() -> bool:
	if not _begin_random_batch():
		return false
	var succeeded := (
		_advance_original_update_in_batch()
		if random_batch_trace_enabled
		else _advance_original_update_fast()
	)
	if not succeeded:
		_cancel_random_batch()
		return false
	return _commit_random_batch()


func _advance_original_update_in_batch() -> bool:
	tick_counter += 1
	var flash_gate := _next_random(0x0005FF45)
	if flash_gate < 0:
		return false
	if flash_gate % 500 == 46:
		flash_active = true
		flash_frame = 0
	if tick_counter >= 80:
		var weather_gate := _next_random(0x0005FF65)
		if weather_gate < 0:
			return false
		if weather_gate % 250 == 30:
			tick_counter = 0
			weather_phase_increasing = not weather_phase_increasing
	if weather_phase_increasing:
		weather_phase = mini(weather_phase + 1, 8)
	else:
		weather_phase = maxi(weather_phase - 1, 0)
	if stored_width != int(LOGICAL_SIZE.x):
		if not _reset_original_particles():
			return false
	stored_width = int(LOGICAL_SIZE.x)
	stored_height = int(LOGICAL_SIZE.y)
	var divisor := 9 - weather_phase
	var secondary_visible := floori(
		float(SECONDARY_COUNT) / float(divisor)
	)
	for index: int in range(secondary_visible):
		if (
			_next_random(0x000600F0) < 0
			or _next_random(0x00060105) < 0
		):
			return false
	var primary_visible := floori(
		float(PRIMARY_COUNT) / float(divisor)
	)
	for index: int in range(primary_visible):
		if not _advance_primary_particle(index):
			return false
	for index: int in range(secondary_visible):
		if not _advance_secondary_particle(index):
			return false
	if flash_active:
		flash_frame += 1
		if flash_frame >= 6:
			flash_active = false
			flash_frame = 0
	return true


func _advance_original_update_fast() -> bool:
	var state := random_batch_state
	var draw_count := 0
	tick_counter += 1
	state = int((state * 214013 + 2531011) & 0xFFFFFFFF)
	draw_count += 1
	var flash_gate := int((state >> 16) & 0x7FFF)
	if flash_gate % 500 == 46:
		flash_active = true
		flash_frame = 0
	if tick_counter >= 80:
		state = int((state * 214013 + 2531011) & 0xFFFFFFFF)
		draw_count += 1
		var weather_gate := int((state >> 16) & 0x7FFF)
		if weather_gate % 250 == 30:
			tick_counter = 0
			weather_phase_increasing = not weather_phase_increasing
	if weather_phase_increasing:
		weather_phase = mini(weather_phase + 1, 8)
	else:
		weather_phase = maxi(weather_phase - 1, 0)
	if stored_width != int(LOGICAL_SIZE.x):
		for index: int in range(PRIMARY_COUNT):
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			primary_positions[index] = Vector2.ZERO
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			primary_alphas[index] = (
				int((state >> 16) & 0x7FFF) % 60 + 100
			)
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			primary_lifetimes[index] = (
				int((state >> 16) & 0x7FFF) % 250 + 250
			)
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			primary_speeds[index] = (
				int((state >> 16) & 0x7FFF) % 8 + 6
			)
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			primary_sizes[index] = (
				int((state >> 16) & 0x7FFF)
				% maxi(PRIMARY_MAX_SIZE - 8, 1)
				+ 8
			)
			draw_count += 6
		for index: int in range(SECONDARY_COUNT):
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			secondary_positions[index] = Vector2.ZERO
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			secondary_alphas[index] = (
				(int((state >> 16) & 0x7FFF) % 70 - 76)
				& 0xFF
			)
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			secondary_lifetimes[index] = (
				int((state >> 16) & 0x7FFF) % 2 + 1
			)
			draw_count += 4
	stored_width = int(LOGICAL_SIZE.x)
	stored_height = int(LOGICAL_SIZE.y)
	var divisor := 9 - weather_phase
	var secondary_visible := floori(
		float(SECONDARY_COUNT) / float(divisor)
	)
	for _index: int in range(secondary_visible):
		state = int((state * 214013 + 2531011) & 0xFFFFFFFF)
		state = int((state * 214013 + 2531011) & 0xFFFFFFFF)
		draw_count += 2
	var primary_visible := floori(
		float(PRIMARY_COUNT) / float(divisor)
	)
	for index: int in range(primary_visible):
		var particle_position := primary_positions[index]
		particle_position += Vector2(
			-float(primary_speeds[index]) * WIND_DIRECTION.x,
			float(primary_speeds[index]) * WIND_DIRECTION.y,
		)
		state = int((state * 214013 + 2531011) & 0xFFFFFFFF)
		var left := int((state >> 16) & 0x7FFF)
		state = int((state * 214013 + 2531011) & 0xFFFFFFFF)
		var right := int((state >> 16) & 0x7FFF)
		var tail_span := maxi(
			left % 19 - right % 20 + 21,
			1,
		)
		state = int((state * 214013 + 2531011) & 0xFFFFFFFF)
		var tail := int((state >> 16) & 0x7FFF)
		draw_count += 3
		primary_lifetimes[index] = (
			primary_lifetimes[index]
			- right % 20
			- tail % tail_span
		)
		primary_positions[index] = particle_position
		if (
			primary_lifetimes[index] <= 0
			or particle_position.x < 0.0
			or particle_position.x > float(stored_width)
			or particle_position.y < 0.0
			or particle_position.y > float(stored_height)
		):
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			var x_value := int((state >> 16) & 0x7FFF)
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			var y_value := int((state >> 16) & 0x7FFF)
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			var alpha := int((state >> 16) & 0x7FFF)
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			var lifetime := int((state >> 16) & 0x7FFF)
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			var speed := int((state >> 16) & 0x7FFF)
			state = int(
				(state * 214013 + 2531011) & 0xFFFFFFFF
			)
			var particle_size := int((state >> 16) & 0x7FFF)
			draw_count += 6
			primary_positions[index] = Vector2(
				float(x_value % maxi(stored_width, 1)),
				float(
					y_value % maxi(stored_height - 80, 1)
				),
			)
			primary_alphas[index] = alpha % 80 + 80
			primary_lifetimes[index] = lifetime % 250 + 250
			primary_speeds[index] = speed % 8 + 6
			primary_sizes[index] = (
				particle_size
				% maxi(PRIMARY_MAX_SIZE - 8, 1)
				+ 8
			)
	for index: int in range(secondary_visible):
		secondary_lifetimes[index] -= 1
		if secondary_lifetimes[index] != 0:
			continue
		state = int((state * 214013 + 2531011) & 0xFFFFFFFF)
		var x_value := int((state >> 16) & 0x7FFF)
		state = int((state * 214013 + 2531011) & 0xFFFFFFFF)
		var y_value := int((state >> 16) & 0x7FFF)
		state = int((state * 214013 + 2531011) & 0xFFFFFFFF)
		var alpha := int((state >> 16) & 0x7FFF)
		state = int((state * 214013 + 2531011) & 0xFFFFFFFF)
		var lifetime := int((state >> 16) & 0x7FFF)
		draw_count += 4
		secondary_positions[index] = Vector2(
			float(x_value % maxi(stored_width, 1)),
			float(y_value % maxi(stored_height, 1)),
		)
		secondary_alphas[index] = (
			(alpha % 70 - 76) & 0xFF
		)
		secondary_lifetimes[index] = lifetime % 2 + 1
	if flash_active:
		flash_frame += 1
		if flash_frame >= 6:
			flash_active = false
			flash_frame = 0
	random_batch_state = state
	random_batch_draw_count = draw_count
	return true


func _begin_random_batch() -> bool:
	if (
		random_source == null
		or not is_instance_valid(random_source)
		or not random_source.has_method(
			"commit_legacy_ambient_crt_random_batch"
		)
	):
		return false
	random_batch_state_before = int(
		random_source.get("legacy_crt_random_state")
	)
	random_batch_state = random_batch_state_before
	random_batch_call_sites = PackedInt32Array()
	random_batch_draw_count = 0
	random_batch_trace_enabled = bool(
		random_source.get("legacy_crt_random_trace_enabled")
	) or bool(
		random_source.get("legacy_crt_random_parity_trace_enabled")
	)
	random_batch_active = true
	return true


func _commit_random_batch() -> bool:
	if not random_batch_active:
		return false
	random_batch_active = false
	return bool(random_source.call(
		"commit_legacy_ambient_crt_random_batch",
		random_batch_state_before,
		random_batch_state,
		random_batch_call_sites,
		random_batch_draw_count,
	))


func _cancel_random_batch() -> void:
	random_batch_active = false
	random_batch_call_sites = PackedInt32Array()
	random_batch_draw_count = 0
	random_batch_trace_enabled = false


func _reset_original_particles() -> bool:
	for index: int in range(PRIMARY_COUNT):
		if (
			_next_random(0x0005FD2C) < 0
			or _next_random(0x0005FD41) < 0
		):
			return false
		primary_positions[index] = Vector2.ZERO
		var alpha := _next_random(0x0005FD54)
		var lifetime := _next_random(0x0005FD6A)
		var speed := _next_random(0x0005FD7F)
		var particle_size := _next_random(0x0005FDA8)
		if (
			alpha < 0
			or lifetime < 0
			or speed < 0
			or particle_size < 0
		):
			return false
		primary_alphas[index] = alpha % 60 + 100
		primary_lifetimes[index] = lifetime % 250 + 250
		primary_speeds[index] = speed % 8 + 6
		primary_sizes[index] = (
			particle_size % maxi(PRIMARY_MAX_SIZE - 8, 1) + 8
		)
	for index: int in range(SECONDARY_COUNT):
		if (
			_next_random(0x0005FDDB) < 0
			or _next_random(0x0005FDEE) < 0
		):
			return false
		secondary_positions[index] = Vector2.ZERO
		var alpha := _next_random(0x0005FE02)
		var lifetime := _next_random(0x0005FE19)
		if mini(alpha, lifetime) < 0:
			return false
		secondary_alphas[index] = (alpha % 70 - 76) & 0xFF
		secondary_lifetimes[index] = lifetime % 2 + 1
	return true


func _advance_primary_particle(index: int) -> bool:
	var particle_position := primary_positions[index]
	particle_position += Vector2(
		-float(primary_speeds[index]) * WIND_DIRECTION.x,
		float(primary_speeds[index]) * WIND_DIRECTION.y,
	)
	var left := _next_random(0x000601D6)
	var right := _next_random(0x000601E5)
	if mini(left, right) < 0:
		return false
	var tail_span := maxi(left % 19 - right % 20 + 21, 1)
	var tail := _next_random(0x00060202)
	if tail < 0:
		return false
	primary_lifetimes[index] = (
		primary_lifetimes[index]
		- right % 20
		- tail % tail_span
	)
	primary_positions[index] = particle_position
	if (
		primary_lifetimes[index] <= 0
		or particle_position.x < 0.0
		or particle_position.x > float(stored_width)
		or particle_position.y < 0.0
		or particle_position.y > float(stored_height)
	):
		return _respawn_primary_particle(index)
	return true


func _respawn_primary_particle(index: int) -> bool:
	var x_value := _next_random(0x0006026D)
	var y_value := _next_random(0x00060291)
	var alpha := _next_random(0x000602A7)
	var lifetime := _next_random(0x000602BC)
	var speed := _next_random(0x000602D1)
	var particle_size := _next_random(0x000602FA)
	if (
		x_value < 0
		or y_value < 0
		or alpha < 0
		or lifetime < 0
		or speed < 0
		or particle_size < 0
	):
		return false
	primary_positions[index] = Vector2(
		float(x_value % maxi(stored_width, 1)),
		float(y_value % maxi(stored_height - 80, 1)),
	)
	primary_alphas[index] = alpha % 80 + 80
	primary_lifetimes[index] = lifetime % 250 + 250
	primary_speeds[index] = speed % 8 + 6
	primary_sizes[index] = (
		particle_size % maxi(PRIMARY_MAX_SIZE - 8, 1) + 8
	)
	return true


func _advance_secondary_particle(index: int) -> bool:
	secondary_lifetimes[index] -= 1
	if secondary_lifetimes[index] != 0:
		return true
	var x_value := _next_random(0x00060374)
	var y_value := _next_random(0x00060396)
	var alpha := _next_random(0x000603AD)
	var lifetime := _next_random(0x000603C4)
	if (
		x_value < 0
		or y_value < 0
		or alpha < 0
		or lifetime < 0
	):
		return false
	secondary_positions[index] = Vector2(
		float(x_value % maxi(stored_width, 1)),
		float(y_value % maxi(stored_height, 1)),
	)
	secondary_alphas[index] = (alpha % 70 - 76) & 0xFF
	secondary_lifetimes[index] = lifetime % 2 + 1
	return true


func _next_random(call_site_rva: int) -> int:
	if not random_batch_active:
		return -1
	random_batch_state = int(
		(
			random_batch_state * 214013
			+ 2531011
		)
		& 0xFFFFFFFF
	)
	random_batch_draw_count += 1
	if random_batch_trace_enabled:
		random_batch_call_sites.append(call_site_rva)
	return int((random_batch_state >> 16) & 0x7FFF)


func _create_particle_multimeshes() -> void:
	if primary_multimesh_instance != null:
		return
	primary_multimesh_instance = MultiMeshInstance2D.new()
	primary_multimesh_instance.name = "PrimaryParticleBatch"
	primary_multimesh_instance.multimesh = _particle_multimesh(
		PRIMARY_COUNT
	)
	add_child(primary_multimesh_instance)
	secondary_multimesh_instance = MultiMeshInstance2D.new()
	secondary_multimesh_instance.name = "SecondaryParticleBatch"
	secondary_multimesh_instance.multimesh = _particle_multimesh(
		SECONDARY_COUNT
	)
	add_child(secondary_multimesh_instance)


static func _particle_multimesh(
	instance_count: int,
) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = instance_count
	multimesh.visible_instance_count = 0
	return multimesh


func _update_particle_multimeshes() -> void:
	if (
		primary_multimesh_instance == null
		or secondary_multimesh_instance == null
		or primary_multimesh_instance.multimesh == null
		or secondary_multimesh_instance.multimesh == null
	):
		return
	var primary_multimesh := (
		primary_multimesh_instance.multimesh
	)
	var secondary_multimesh := (
		secondary_multimesh_instance.multimesh
	)
	if (
		not visible
		or OS.get_environment(
			"M1937_REMAKE_HIDE_AMBIENT_PARTICLES"
		) == "1"
		or stored_width <= 0
		or stored_height <= 0
	):
		primary_multimesh.visible_instance_count = 0
		secondary_multimesh.visible_instance_count = 0
		return
	var scale_factor := size / LOGICAL_SIZE
	var divisor := 9 - weather_phase
	var primary_visible := floori(
		float(PRIMARY_COUNT) / float(divisor)
	)
	var primary_width := maxf(scale_factor.x, 0.75)
	for index: int in range(primary_visible):
		var start := primary_positions[index] * scale_factor
		var offset := Vector2(
			-WIND_DIRECTION.x,
			WIND_DIRECTION.y,
		) * (
			float(primary_sizes[index])
			* maxf(scale_factor.y, 0.25)
		)
		primary_multimesh.set_instance_transform_2d(
			index,
			Transform2D(
				offset.angle(),
				Vector2(offset.length(), primary_width),
				0.0,
				start + offset * 0.5,
			),
		)
		primary_multimesh.set_instance_color(
			index,
			Color(
				0.78,
				0.86,
				0.92,
				float(primary_alphas[index]) / 255.0,
			),
		)
	primary_multimesh.visible_instance_count = primary_visible
	var secondary_visible := floori(
		float(SECONDARY_COUNT) / float(divisor)
	)
	var secondary_size := maxf(
		1.0,
		minf(scale_factor.x, scale_factor.y),
	) * 2.0
	for index: int in range(secondary_visible):
		secondary_multimesh.set_instance_transform_2d(
			index,
			Transform2D(
				0.0,
				Vector2(secondary_size, secondary_size),
				0.0,
				secondary_positions[index] * scale_factor,
			),
		)
		secondary_multimesh.set_instance_color(
			index,
			Color(
				0.84,
				0.89,
				0.94,
				float(secondary_alphas[index]) / 255.0,
			),
		)
	secondary_multimesh.visible_instance_count = secondary_visible


func _draw() -> void:
	if (
		not visible
		or not flash_active
		or stored_width <= 0
		or stored_height <= 0
	):
		return
	var flash_alpha := (
		0.12 if flash_frame % 2 == 0 else 0.04
	)
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(1.0, 1.0, 1.0, flash_alpha),
	)
