class_name MissionStatistics
extends RefCounted

const SCHEMA_VERSION := 1

var level_id := ""
var started_at_msec := 0
var counters: Dictionary = {}


func begin_mission(new_level_id: String) -> void:
	level_id = new_level_id
	started_at_msec = Time.get_ticks_msec()
	counters = {
		"commands": 0,
		"moves": 0,
		"attacks": 0,
		"hits": 0,
		"misses": 0,
		"enemies_eliminated": 0,
		"player_losses": 0,
		"pickups": 0,
		"alarms": 0,
		"saves": 0,
		"checkpoint_loads": 0,
	}


func observe_command(command: Dictionary) -> void:
	if level_id.is_empty():
		return
	counters["commands"] = int(counters.get("commands", 0)) + 1
	var name := str(command.get("name", ""))
	if name.contains("move") or name in ["formation_order", "context_ground"]:
		increment("moves")
	elif name.contains("save"):
		increment("saves")
	elif name.contains("load") or name.contains("checkpoint_restore"):
		increment("checkpoint_loads")


func observe_event(event: Dictionary) -> void:
	var name := str(event.get("name", ""))
	match name:
		"attack_started":
			var payload := event.get("payload", {}) as Dictionary
			if bool(payload.get("player", false)):
				increment("attacks")
		"attack_hit", "projectile_hit":
			var payload := event.get("payload", {}) as Dictionary
			if _payload_is_player_attack(payload):
				increment("hits")
		"attack_missed", "projectile_miss":
			var payload := event.get("payload", {}) as Dictionary
			if _payload_is_player_attack(payload):
				increment("misses")
		"enemy_eliminated":
			increment("enemies_eliminated")
		"player_eliminated":
			increment("player_losses")
		"item_picked_up", "pickup_collected":
			increment("pickups")
		"alarm_raised", "global_alarm":
			increment("alarms")


func _payload_is_player_attack(payload: Dictionary) -> bool:
	if payload.has("player"):
		return bool(payload["player"])
	# Imported player scene indices use the negative runtime range while
	# ordinary level actors use non-negative source indices.
	return int(payload.get("attacker_scene_index", 0)) < 0


func increment(counter: String, amount: int = 1) -> void:
	if counter.is_empty():
		return
	counters[counter] = maxi(int(counters.get(counter, 0)) + amount, 0)


func snapshot() -> Dictionary:
	var result := counters.duplicate(true)
	result["schema_version"] = SCHEMA_VERSION
	result["level_id"] = level_id
	result["elapsed_msec"] = (
		maxi(Time.get_ticks_msec() - started_at_msec, 0)
		if started_at_msec > 0
		else 0
	)
	return result
