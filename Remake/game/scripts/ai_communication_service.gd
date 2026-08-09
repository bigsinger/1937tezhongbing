class_name AiCommunicationService
extends RefCounted

const PROPAGATION_SHOUT := "shout"
const PROPAGATION_SOUND := "sound"
const PROPAGATION_ALARM := "alarm"
const PROPAGATION_RADIO := "radio"


func recipients_in_radius(
	source_position: Vector2,
	radius: float,
	candidates: Array[Node2D],
	limit: int = 64,
	excluded_actor_id: int = -1,
	transmission_check: Callable = Callable(),
) -> Array[int]:
	var scored: Array[Dictionary] = []
	var radius_squared := maxf(radius, 0.0) * maxf(radius, 0.0)
	for candidate: Node2D in candidates:
		if candidate == null or not is_instance_valid(candidate) or not bool(candidate.get("is_alive")):
			continue
		var actor_id := int(candidate.get("scene_index"))
		if actor_id == excluded_actor_id:
			continue
		var distance := candidate.position.distance_squared_to(source_position)
		if (
			distance <= radius_squared
			and (
				not transmission_check.is_valid()
				or bool(transmission_check.call(source_position, candidate.position))
			)
		):
			scored.append({"actor_id": actor_id, "distance": distance})
	scored.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if not is_equal_approx(float(left["distance"]), float(right["distance"])):
				return float(left["distance"]) < float(right["distance"])
			return int(left["actor_id"]) < int(right["actor_id"])
	)
	var result: Array[int] = []
	for index: int in range(mini(scored.size(), maxi(limit, 0))):
		result.append(int(scored[index]["actor_id"]))
	return result


func can_transmit(
	mode: String,
	distance: float,
	radius: float,
	has_radio: bool = false,
	alarm_active: bool = false,
	insulated: bool = false,
) -> bool:
	match mode:
		PROPAGATION_RADIO:
			return has_radio
		PROPAGATION_ALARM:
			return alarm_active
		PROPAGATION_SHOUT, PROPAGATION_SOUND:
			return distance <= maxf(radius, 0.0) and (mode == PROPAGATION_SOUND or not insulated)
	return false
