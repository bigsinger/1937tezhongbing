class_name LegacyAnimationAudioRules
extends RefCounted

## Exact sound-dispatch rules from M1937.exe sub_41D6F0 and sub_427C80.
## A frame group's parameters[8] is a one-based 1937Sound.slf index. Conversion
## resolves it to sound_gfl_index so runtime code never guesses from filenames.

enum RequestMode {
	NONE,
	CONTINUOUS,
	ENTER_FRAME_ONE,
	ENTER_LAST_FRAME,
}

const LAST_FRAME_ACTIONS: Array[int] = [5, 6, 9, 10, 12, 13, 14, 15]


static func request_mode_for_action(action_index: int) -> int:
	if action_index < 0:
		return RequestMode.NONE
	if action_index in LAST_FRAME_ACTIONS:
		return RequestMode.ENTER_LAST_FRAME
	if action_index == 0:
		return RequestMode.ENTER_FRAME_ONE
	# sub_41D6F0 passes 1 to sub_427CB0 for every remaining non-zero
	# action. sub_427CB0 requests the sound on every actor update while that
	# serial stays active; the sound manager itself suppresses busy buffers.
	return RequestMode.CONTINUOUS


static func group_action_index(group: Dictionary) -> int:
	var explicit: Variant = group.get("action_index")
	if explicit is int:
		return int(explicit)
	if explicit is float and is_finite(float(explicit)):
		var value := float(explicit)
		if value == float(int(value)):
			return int(value)
	var serial: Variant = group.get("serial_id")
	if serial is int and int(serial) >= 0:
		return int(serial) / 9
	if serial is float and is_finite(float(serial)):
		var value := float(serial)
		if value >= 0.0 and value == float(int(value)):
			return int(value) / 9
	return -1


static func sound_gfl_index(group: Dictionary) -> int:
	var raw: Variant = group.get("sound_gfl_index")
	if raw is int:
		return int(raw) if int(raw) > 0 else -1
	if raw is float and is_finite(float(raw)):
		var value := float(raw)
		if value > 0.0 and value == float(int(value)):
			return int(value)
	return -1


static func requests_continuously(group: Dictionary) -> bool:
	return (
		sound_gfl_index(group) > 0
		and request_mode_for_action(group_action_index(group))
			== RequestMode.CONTINUOUS
	)


static func transition_requests_sound(
	group: Dictionary,
	previous_frame_index: int,
	current_frame_index: int,
) -> bool:
	if sound_gfl_index(group) <= 0:
		return false
	var frame_count := _group_frame_count(group)
	if frame_count <= 0:
		return false
	var mode := request_mode_for_action(group_action_index(group))
	match mode:
		RequestMode.ENTER_FRAME_ONE:
			return (
				frame_count > 1
				and current_frame_index == 1
				and previous_frame_index != 1
			)
		RequestMode.ENTER_LAST_FRAME:
			var last_frame := frame_count - 1
			return (
				current_frame_index == last_frame
				and previous_frame_index != last_frame
			)
	return false


static func _group_frame_count(group: Dictionary) -> int:
	var frames: Variant = group.get("frames")
	if frames is Array:
		return (frames as Array).size()
	var raw_count: Variant = group.get("frame_count")
	if raw_count is int:
		return maxi(int(raw_count), 0)
	if raw_count is float and is_finite(float(raw_count)):
		var value := float(raw_count)
		if value == float(int(value)):
			return maxi(int(value), 0)
	return 0
