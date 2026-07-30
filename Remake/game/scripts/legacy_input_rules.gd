class_name LegacyInputRules
extends RefCounted

## Deterministic input rules recovered from the original 2001 executable.
##
## Evidence:
## - sub_448E40 polls DirectInput and produces mouse/key transition fields;
## - sub_43E050 consumes the keyboard matrix;
## - sub_44C800 owns right-button drag selection and release cancellation;
## - sub_44C9B0 owns the two-pixel client-edge ramp;
## - sub_44FED0 submits world commands on the left-button press transition.
##
## These helpers never capture, warp, clip, or synthesize the operating-system
## pointer. They only classify events and advance process-local game state.

const PHASE_PRESS := "press"
const PHASE_RELEASE := "release"
const PHASE_HELD := "held"

const ORIGINAL_EDGE_LAST_INNER_COORDINATE := 1.0
const ORIGINAL_SCROLL_RESPONSE_DIVISOR := 8

const WORLD_LEFT_COMMAND_PHASE := PHASE_PRESS
const WORLD_RIGHT_SELECTION_PHASE := PHASE_RELEASE

# DirectInput DIK scan codes read from ValueName[84 + scan_code].
const DIRECT_INPUT_SCAN_CODES := {
	"pause": 0x01,
	"weapon_1": 0x02,
	"weapon_2": 0x03,
	"weapon_3": 0x04,
	"weapon_4": 0x05,
	"weapon_5": 0x06,
	"weapon_6": 0x07,
	"weapon_7": 0x08,
	"weapon_8": 0x09,
	"weapon_9": 0x0A,
	"weapon_10": 0x0B,
	"weapon_inventory": 0x11,
	"toggle_run": 0x13,
	"force_target_ctrl": 0x1D,
	"item_inventory": 0x1E,
	"sight_mode": 0x1F,
	"toggle_crawl": 0x2E,
	"burial_mode": 0x30,
	"minimap": 0x32,
	"guide": 0x3B,
	"select_1": 0x3C,
	"select_2": 0x3D,
	"select_3": 0x3E,
	"select_4": 0x3F,
	"select_5": 0x40,
	"briefing": 0x41,
	"debug_load_m010": 0x42,
	"force_target_up": 0xC8,
}

const RELEASE_ACTIONS := {
	"pause": true,
	"guide": true,
	"briefing": true,
	"toggle_run": true,
	"toggle_crawl": true,
	"weapon_inventory": true,
	"item_inventory": true,
	"sight_mode": true,
	"burial_mode": true,
	"minimap": true,
}

const PRESS_ACTIONS := {
	"select_1": true,
	"select_2": true,
	"select_3": true,
	"select_4": true,
	"select_5": true,
	"weapon_1": true,
	"weapon_2": true,
	"weapon_3": true,
	"weapon_4": true,
	"weapon_5": true,
	"weapon_6": true,
	"weapon_7": true,
	"weapon_8": true,
	"weapon_9": true,
	"weapon_10": true,
}

const HELD_ACTIONS := {
	"force_target_ctrl": true,
	"force_target_up": true,
}

enum CursorSerial {
	NORMAL = 0,
	MOVE = 1,
	FORCE_TARGET = 2,
	INTERACT = 3,
	BURIAL = 4,
	ALTERNATE_INTERACT = 6,
	SIGHT = 8,
	OUTSIDE_WORLD = 9,
	BLOCKED = 10,
}

enum EdgeDirection {
	NONE = 0,
	NORTH = 1,
	NORTHEAST = 2,
	EAST = 3,
	SOUTHEAST = 4,
	SOUTH = 5,
	SOUTHWEST = 6,
	WEST = 7,
	NORTHWEST = 8,
}


static func trigger_phase_for_action(action: String) -> String:
	if RELEASE_ACTIONS.has(action):
		return PHASE_RELEASE
	if PRESS_ACTIONS.has(action):
		return PHASE_PRESS
	if HELD_ACTIONS.has(action):
		return PHASE_HELD
	# Remake-only extensions are ordinary press-edge commands.
	return PHASE_PRESS


static func direct_input_scan_code_for_action(action: String) -> int:
	return int(DIRECT_INPUT_SCAN_CODES.get(action, -1))


static func should_trigger_for_event(action: String, event: InputEventKey) -> bool:
	if action.is_empty() or event.echo:
		return false
	match trigger_phase_for_action(action):
		PHASE_PRESS:
			return event.pressed
		PHASE_RELEASE:
			return not event.pressed
		_:
			# Held channels are sampled from the current key state, not emitted
			# as commands on either transition.
			return false


static func mouse_button_transition(previous_down: bool, current_down: bool) -> Dictionary:
	return {
		"pressed": current_down and not previous_down,
		"down": current_down,
		"released": previous_down and not current_down,
	}


static func should_submit_world_left(current_down: bool) -> bool:
	return current_down and WORLD_LEFT_COMMAND_PHASE == PHASE_PRESS


static func should_finish_world_right(current_down: bool) -> bool:
	return not current_down and WORLD_RIGHT_SELECTION_PHASE == PHASE_RELEASE


static func edge_direction_for_position(
	mouse_position: Vector2,
	viewport_size: Vector2,
	last_inner_coordinate: float = ORIGINAL_EDGE_LAST_INNER_COORDINATE,
) -> Vector2:
	if (
		viewport_size.x <= 0.0
		or viewport_size.y <= 0.0
		or mouse_position.x < 0.0
		or mouse_position.y < 0.0
		or mouse_position.x >= viewport_size.x
		or mouse_position.y >= viewport_size.y
	):
		return Vector2.ZERO
	var edge := maxf(last_inner_coordinate, 0.0)
	var direction := Vector2.ZERO
	if mouse_position.x <= edge:
		direction.x = -1.0
	elif mouse_position.x >= viewport_size.x - 1.0:
		direction.x = 1.0
	if mouse_position.y <= edge:
		direction.y = -1.0
	elif mouse_position.y >= viewport_size.y - 1.0:
		direction.y = 1.0
	return direction


static func edge_direction_code(direction: Vector2) -> int:
	var x := signf(direction.x)
	var y := signf(direction.y)
	if x == 0.0 and y < 0.0:
		return EdgeDirection.NORTH
	if x > 0.0 and y < 0.0:
		return EdgeDirection.NORTHEAST
	if x > 0.0 and y == 0.0:
		return EdgeDirection.EAST
	if x > 0.0 and y > 0.0:
		return EdgeDirection.SOUTHEAST
	if x == 0.0 and y > 0.0:
		return EdgeDirection.SOUTH
	if x < 0.0 and y > 0.0:
		return EdgeDirection.SOUTHWEST
	if x < 0.0 and y == 0.0:
		return EdgeDirection.WEST
	if x < 0.0 and y < 0.0:
		return EdgeDirection.NORTHWEST
	return EdgeDirection.NONE


static func advance_scroll_strength(
	current_strength: float,
	at_edge: bool,
	tick_fraction: float = 1.0,
	response_divisor: int = ORIGINAL_SCROLL_RESPONSE_DIVISOR,
) -> float:
	var divisor := maxi(response_divisor, 1)
	var step := maxf(tick_fraction, 0.0) / float(divisor)
	return clampf(
		current_strength + (step if at_edge else -step),
		0.0,
		1.0,
	)


static func advance_original_integer_scroll_velocity(
	current_velocity: int,
	velocity_limit: int,
	at_edge: bool,
	response_divisor: int = ORIGINAL_SCROLL_RESPONSE_DIVISOR,
) -> int:
	var safe_limit := maxi(velocity_limit, 0)
	var divisor := maxi(response_divisor, 1)
	# This intentionally preserves the original C integer division, including
	# the zero step produced by a limit smaller than the divisor.
	var step := safe_limit / divisor
	return clampi(
		current_velocity + (step if at_edge else -step),
		0,
		safe_limit,
	)


static func context_cursor_serial(
	burial_mode: bool,
	sight_mode: bool,
	has_selected_actor: bool,
	force_target_held: bool,
	hovering_interactable: bool,
	hovering_enemy: bool,
	ground_is_walkable: bool,
	pointer_inside_world: bool = true,
) -> int:
	if not pointer_inside_world:
		return CursorSerial.NORMAL
	# sub_44C050 evaluates B before S's ordinary ground/target path.
	if burial_mode:
		return CursorSerial.BURIAL
	if sight_mode:
		return CursorSerial.SIGHT
	if not has_selected_actor:
		return CursorSerial.NORMAL
	if force_target_held:
		return CursorSerial.FORCE_TARGET
	if hovering_interactable:
		return CursorSerial.INTERACT
	if hovering_enemy:
		return CursorSerial.FORCE_TARGET
	return CursorSerial.MOVE if ground_is_walkable else CursorSerial.BLOCKED


static func fallback_cursor_shape(serial_id: int) -> Input.CursorShape:
	match serial_id:
		CursorSerial.MOVE, CursorSerial.INTERACT, CursorSerial.ALTERNATE_INTERACT:
			return Input.CURSOR_POINTING_HAND
		CursorSerial.FORCE_TARGET:
			return Input.CURSOR_CROSS
		CursorSerial.BURIAL:
			return Input.CURSOR_POINTING_HAND
		CursorSerial.SIGHT:
			return Input.CURSOR_HELP
		CursorSerial.BLOCKED:
			return Input.CURSOR_FORBIDDEN
		_:
			return Input.CURSOR_ARROW
