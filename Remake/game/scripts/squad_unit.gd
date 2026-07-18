class_name SquadUnit
extends Node2D

const BASE_SPRITE_TICK_SECONDS := 0.085
const DEFAULT_REPLAN_BLOCKED_SECONDS := 0.25
const COMBAT_REPATH_SECONDS := 0.40
const HURT_REACTION_SECONDS := 0.18
const TACTICAL_SENSES_SCRIPT: Script = preload("res://scripts/tactical_senses.gd")
const PROJECTILE_PROFILES: Script = preload("res://scripts/projectile_profiles.gd")
const COMBAT_INVENTORY_SCRIPT: Script = preload("res://scripts/combat_inventory.gd")

enum CombatAction { NONE, ATTACK, RELOAD, DEATH }

signal attack_started(
	attacker: Node2D,
	target: Node2D,
	attack_type: int,
	alert_radius: float,
)
signal attack_hit(attacker: Node2D, target: Node2D, attack_type: int, damage: int)
signal projectile_requested(attacker: Node2D, target: Node2D, weapon_profile: Dictionary)
signal damage_received(unit: Node2D, attacker: Node2D, damage: int, remaining_hit_points: int)
signal died(unit: Node2D, killer: Node2D)
signal ammo_changed(unit: Node2D, magazine: int, reserve: int)

@export_range(0.0, 1000.0, 1.0, "or_greater") var move_speed: float = 150.0

var display_name: String = "队员"
var body_color: Color = Color.WHITE
var selected: bool = false
var target_position: Vector2
var movement_path := PackedVector2Array()
var movement_path_index := 0
var was_moving := false
var blocked_elapsed := 0.0
var blocked_replan_seconds := DEFAULT_REPLAN_BLOCKED_SECONDS
var is_crawling := false
var is_alive := true
var faction_id := 3
var current_hit_points := 8
var maximum_hit_points := 8
var scene_index := -1
var dynamic_occupancy: RefCounted
var dynamic_registered := false
var sprite_texture: Texture2D
var sprite_anchor := Vector2.ZERO
var movement_groups: Array[Dictionary] = []
var idle_groups: Array[Dictionary] = []
var animation_group_index := 7
var animation_frame_index := 0
var animation_elapsed := 0.0
var weapon_profile: Dictionary = {}
var attack_groups: Array[Dictionary] = []
var death_groups: Array[Dictionary] = []
var magazine_ammo := 0
var reserve_ammo := 0
var infinite_ammo := false
var combat_target: Node2D
var auto_combat_enabled := false
var combat_repath_elapsed := COMBAT_REPATH_SECONDS
var attack_cooldown_remaining := 0.0
var combat_action := CombatAction.NONE
var action_frame_index := 0
var action_frame_elapsed := 0.0
var action_finished := false
var reload_remaining := 0.0
var pending_hit_target: Node2D
var pending_hit_resolved := false
var hurt_remaining := 0.0
var death_emitted := false
var combat_inventory: RefCounted
var attack_groups_by_action: Dictionary = {}
var inventory_weapon_order: Array[String] = []


func configure(
	new_name: String,
	color: Color,
	start_position: Vector2,
	texture: Texture2D = null,
	new_movement_groups: Array[Dictionary] = [],
	new_idle_groups: Array[Dictionary] = [],
	new_scene_index: int = -1,
	new_dynamic_occupancy: RefCounted = null,
	new_source_reference_position: Variant = null,
) -> void:
	display_name = new_name
	body_color = color
	sprite_texture = texture
	movement_groups = new_movement_groups
	idle_groups = new_idle_groups
	scene_index = new_scene_index
	dynamic_occupancy = new_dynamic_occupancy
	position = start_position
	target_position = start_position
	movement_path.clear()
	movement_path_index = 0
	was_moving = false
	blocked_elapsed = 0.0
	dynamic_registered = false
	combat_target = null
	auto_combat_enabled = false
	combat_action = CombatAction.NONE
	action_finished = false
	hurt_remaining = 0.0
	death_emitted = false
	combat_inventory = null
	attack_groups_by_action.clear()
	inventory_weapon_order.clear()
	is_alive = true
	if (
		dynamic_occupancy != null
		and scene_index >= 0
	):
		dynamic_registered = dynamic_occupancy.register_scene(
			scene_index, start_position, new_source_reference_position
		)
		if not dynamic_registered:
			dynamic_occupancy = null
	z_index = clampi(int(position.y) + 1, -4096, 4095)
	if movement_groups.size() >= 8:
		set_animation_group(7)
		apply_idle_frame()
	elif sprite_texture != null:
		sprite_anchor = sprite_texture.get_size() * 0.5
	queue_redraw()


func configure_combat(
	new_faction_id: int,
	hit_points: int,
	new_weapon_profile: Dictionary,
	new_attack_groups: Array[Dictionary] = [],
	new_death_groups: Array[Dictionary] = [],
	use_infinite_ammo: bool = false,
) -> void:
	faction_id = new_faction_id
	maximum_hit_points = maxi(hit_points, 1)
	current_hit_points = maximum_hit_points
	is_alive = true
	weapon_profile = new_weapon_profile.duplicate(true)
	attack_groups = new_attack_groups
	death_groups = new_death_groups
	infinite_ammo = use_infinite_ammo
	var magazine_capacity := maxi(int(weapon_profile.get("magazine_capacity", 0)), 0)
	magazine_ammo = magazine_capacity
	reserve_ammo = maxi(int(weapon_profile.get("starting_reserve_ammo", 0)), 0)
	combat_inventory = null
	attack_groups_by_action.clear()
	inventory_weapon_order.clear()
	var action_key := str(weapon_profile.get("action_key", ""))
	var ammo_item_id := int(weapon_profile.get("ammo_item_id", 0))
	if (
		not infinite_ammo
		and not action_key.is_empty()
		and COMBAT_INVENTORY_SCRIPT.supports_ammo_item(ammo_item_id)
	):
		combat_inventory = COMBAT_INVENTORY_SCRIPT.new()
		if combat_inventory.register_weapon(action_key, weapon_profile, true):
			attack_groups_by_action[action_key] = new_attack_groups
			inventory_weapon_order.append(action_key)
			_sync_ammo_from_inventory(false)
	combat_target = null
	auto_combat_enabled = false
	combat_repath_elapsed = COMBAT_REPATH_SECONDS
	attack_cooldown_remaining = 0.0
	combat_action = CombatAction.NONE
	action_frame_index = 0
	action_frame_elapsed = 0.0
	action_finished = false
	reload_remaining = 0.0
	pending_hit_target = null
	pending_hit_resolved = false
	hurt_remaining = 0.0
	death_emitted = false
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value and is_alive
	queue_redraw()


func register_inventory_weapon(
	new_weapon_profile: Dictionary,
	new_attack_groups: Array[Dictionary] = [],
	load_profile_defaults: bool = false,
	equip_now: bool = true,
) -> bool:
	if infinite_ammo or new_weapon_profile.is_empty():
		return false
	var action_key := str(new_weapon_profile.get("action_key", ""))
	if action_key.is_empty():
		return false
	if combat_inventory == null:
		combat_inventory = COMBAT_INVENTORY_SCRIPT.new()
	if combat_inventory.weapon_state(action_key).is_empty():
		if not combat_inventory.register_weapon(
			action_key, new_weapon_profile, load_profile_defaults
		):
			return false
		inventory_weapon_order.append(action_key)
	attack_groups_by_action[action_key] = new_attack_groups
	if equip_now:
		return equip_inventory_weapon(action_key)
	_sync_ammo_from_inventory(false)
	return true


func equip_inventory_weapon(action_key: String) -> bool:
	if (
		combat_inventory == null
		or combat_action != CombatAction.NONE
		or not combat_inventory.equip_weapon(action_key)
	):
		return false
	weapon_profile = combat_inventory.active_weapon_profile()
	attack_groups = attack_groups_by_action.get(action_key, []) as Array[Dictionary]
	clear_combat_target()
	_sync_ammo_from_inventory(true)
	apply_idle_frame()
	queue_redraw()
	return true


func equip_attack_type(attack_type: int) -> bool:
	if combat_inventory == null:
		return false
	for action_key: String in inventory_weapon_order:
		if int(combat_inventory.weapon_profile(action_key).get("attack_type", 0)) == attack_type:
			return equip_inventory_weapon(action_key)
	return false


func cycle_inventory_weapon(direction: int = 1) -> bool:
	if combat_inventory == null or inventory_weapon_order.size() < 2:
		return false
	var current_index := inventory_weapon_order.find(combat_inventory.active_weapon_key())
	var next_index := posmod(current_index + (1 if direction >= 0 else -1), inventory_weapon_order.size())
	return equip_inventory_weapon(inventory_weapon_order[next_index])


func add_ammo_item(item_id: int, quantity: int) -> int:
	if combat_inventory == null:
		return 0
	var accepted := int(combat_inventory.add_item(item_id, quantity))
	if accepted > 0:
		_sync_ammo_from_inventory(true)
	return accepted


func ammo_item_count(item_id: int) -> int:
	if combat_inventory == null:
		return 0
	return int(combat_inventory.ammo_item_count(item_id))


func remove_ammo_item(item_id: int, quantity: int) -> int:
	if combat_inventory == null:
		return 0
	var removed := int(combat_inventory.remove_item(item_id, quantity))
	if removed > 0:
		_sync_ammo_from_inventory(true)
	return removed


func has_inventory_weapon(action_key: String) -> bool:
	return combat_inventory != null and not combat_inventory.weapon_state(action_key).is_empty()


func preferred_finite_ammo_item_id() -> int:
	if combat_inventory == null:
		return 0
	var active_state: Dictionary = combat_inventory.weapon_state(
		combat_inventory.active_weapon_key()
	)
	if int(active_state.get("magazine_capacity", 0)) > 0:
		return int(active_state.get("ammo_item_id", 0))
	for action_key: String in inventory_weapon_order:
		var state: Dictionary = combat_inventory.weapon_state(action_key)
		if int(state.get("magazine_capacity", 0)) > 0:
			return int(state.get("ammo_item_id", 0))
	return 0


func inventory_snapshot() -> Dictionary:
	if combat_inventory == null:
		return {}
	return combat_inventory.full_snapshot()


func issue_move(destination: Vector2) -> void:
	issue_path(PackedVector2Array([destination]))


func issue_path(path: PackedVector2Array) -> void:
	movement_path = path.duplicate()
	movement_path_index = 0
	blocked_elapsed = 0.0
	while (
		movement_path_index < movement_path.size()
		and position.is_equal_approx(movement_path[movement_path_index])
	):
		movement_path_index += 1
	if movement_path_index < movement_path.size():
		target_position = movement_path[-1]
	else:
		target_position = position
	queue_redraw()


func cancel_path() -> void:
	if dynamic_occupancy != null and dynamic_registered and scene_index >= 0:
		dynamic_occupancy.release_goal(scene_index)
	movement_path.clear()
	movement_path_index = 0
	target_position = position
	blocked_elapsed = 0.0
	_apply_idle_state()
	queue_redraw()


func issue_attack(target: Node2D) -> bool:
	if not is_alive or not _target_is_alive(target) or weapon_profile.is_empty():
		return false
	combat_target = target
	auto_combat_enabled = true
	combat_repath_elapsed = COMBAT_REPATH_SECONDS
	return true


func clear_combat_target() -> void:
	combat_target = null
	auto_combat_enabled = false
	combat_repath_elapsed = COMBAT_REPATH_SECONDS


func is_combat_alive() -> bool:
	return is_alive


func can_attack_target(target: Node2D) -> bool:
	if (
		not is_alive
		or not _target_is_alive(target)
		or not (
			factions_are_hostile(faction_id, int(target.get("faction_id")))
			or _is_destructible_world_target(target)
		)
		or weapon_profile.is_empty()
		or dynamic_occupancy == null
	):
		return false
	var ignored: Array = [scene_index]
	var target_scene_index := int(target.get("scene_index"))
	if target_scene_index >= 0:
		ignored.append(target_scene_index)
	return TACTICAL_SENSES_SCRIPT.can_attack(
		dynamic_occupancy,
		position,
		target.position,
		weapon_profile,
		ignored,
	)


func _is_destructible_world_target(target: Node2D) -> bool:
	return (
		target != null
		and target.has_method("explosion_payload")
		and target.has_method("take_damage")
	)


static func factions_are_hostile(first_faction: int, second_faction: int) -> bool:
	return (
		(first_faction == 1 and second_faction == 3)
		or (first_faction == 3 and second_faction == 1)
	)


func try_start_attack(target: Node2D) -> bool:
	if (
		not is_alive
		or combat_action != CombatAction.NONE
		or hurt_remaining > 0.0
		or attack_cooldown_remaining > 0.0
		or not can_attack_target(target)
	):
		return false
	var ammo_per_attack := maxi(int(weapon_profile.get("ammo_per_attack", 0)), 0)
	if not infinite_ammo and ammo_per_attack > 0:
		if combat_inventory != null:
			if not combat_inventory.consume_active_attack():
				_start_reload()
				return false
			_sync_ammo_from_inventory(true)
		else:
			if magazine_ammo < ammo_per_attack:
				_start_reload()
				return false
			magazine_ammo -= ammo_per_attack
			ammo_changed.emit(self, magazine_ammo, reserve_ammo)

	var facing := target.position - position
	if not facing.is_zero_approx():
		set_animation_group(direction_group_index(facing))
	cancel_path()
	pending_hit_target = target
	pending_hit_resolved = false
	attack_cooldown_remaining = maxf(
		float(weapon_profile.get("recovery_seconds", 0.5)), 0.05
	)
	attack_started.emit(
		self,
		target,
		int(weapon_profile.get("attack_type", 0)),
		float(weapon_profile.get("alert_radius", 0.0)),
	)
	_start_one_shot(CombatAction.ATTACK, attack_groups)
	if attack_groups.is_empty():
		_resolve_pending_hit()
		combat_action = CombatAction.NONE
		apply_idle_frame()
	return true


func request_reload() -> bool:
	if not is_alive or combat_action != CombatAction.NONE or hurt_remaining > 0.0:
		return false
	return _start_reload()


func take_damage(amount: int, attacker: Node2D = null) -> int:
	if not is_alive or amount <= 0:
		return 0
	var applied := mini(amount, current_hit_points)
	current_hit_points -= applied
	damage_received.emit(self, attacker, applied, current_hit_points)
	_on_damage_taken(attacker)
	if current_hit_points <= 0:
		_die(attacker)
	else:
		_interrupt_combat_action()
		cancel_path()
		hurt_remaining = HURT_REACTION_SECONDS
	queue_redraw()
	return applied


func heal(amount: int) -> int:
	if not is_alive or amount <= 0 or current_hit_points >= maximum_hit_points:
		return 0
	var applied := mini(amount, maximum_hit_points - current_hit_points)
	current_hit_points += applied
	queue_redraw()
	return applied


func _on_damage_taken(_attacker: Node2D) -> void:
	pass


func contains_parent_point(parent_point: Vector2) -> bool:
	return position.distance_squared_to(parent_point) <= 26.0 * 26.0


func _physics_process(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	attack_cooldown_remaining = maxf(attack_cooldown_remaining - safe_delta, 0.0)
	if combat_action != CombatAction.NONE:
		_advance_combat_action(safe_delta)
		return
	if not is_alive:
		return
	if hurt_remaining > 0.0:
		hurt_remaining = maxf(hurt_remaining - safe_delta, 0.0)
		self_modulate = (
			Color(1.0, 0.35, 0.28, 1.0)
			if int(hurt_remaining * 60.0) % 2 == 0
			else Color.WHITE
		)
		if hurt_remaining <= 0.0:
			self_modulate = Color.WHITE
			apply_idle_frame()
		queue_redraw()
		return
	if auto_combat_enabled and _update_auto_combat(safe_delta):
		return

	var previous_position := position
	var next_position := position
	var next_path_index := movement_path_index
	var remaining_distance := maxf(move_speed, 0.0) * safe_delta
	while next_path_index < movement_path.size() and remaining_distance > 0.0:
		var waypoint := movement_path[next_path_index]
		var distance_to_waypoint := next_position.distance_to(waypoint)
		if distance_to_waypoint <= remaining_distance:
			next_position = waypoint
			remaining_distance -= distance_to_waypoint
			next_path_index += 1
		else:
			next_position = next_position.move_toward(waypoint, remaining_distance)
			remaining_distance = 0.0
	if (
		next_position != position
		and dynamic_occupancy != null
		and scene_index >= 0
		and not dynamic_occupancy.try_relocate(scene_index, next_position)
	):
		blocked_elapsed += safe_delta
		if blocked_elapsed >= maxf(blocked_replan_seconds, 0.05):
			blocked_elapsed = 0.0
			var replanned: PackedVector2Array = dynamic_occupancy.find_path_for_scene(
				scene_index, position, target_position
			)
			if not replanned.is_empty():
				issue_path(replanned)
		_apply_idle_state()
		return
	position = next_position
	movement_path_index = next_path_index
	blocked_elapsed = 0.0
	var displacement := position - previous_position
	if not displacement.is_zero_approx():
		set_animation_group(direction_group_index(displacement))
		advance_animation(safe_delta)
		was_moving = true
		z_index = clampi(int(position.y) + 1, -4096, 4095)
		queue_redraw()
	else:
		_apply_idle_state()


func _update_auto_combat(delta: float) -> bool:
	if not _target_is_alive(combat_target):
		clear_combat_target()
		return false
	if can_attack_target(combat_target):
		if movement_path_index < movement_path.size():
			cancel_path()
		if attack_cooldown_remaining <= 0.0:
			try_start_attack(combat_target)
		else:
			_apply_idle_state()
		return true
	combat_repath_elapsed += delta
	if (
		combat_repath_elapsed >= COMBAT_REPATH_SECONDS
		or movement_path_index >= movement_path.size()
	):
		combat_repath_elapsed = 0.0
		if dynamic_occupancy != null and dynamic_registered and scene_index >= 0:
			var path: PackedVector2Array = dynamic_occupancy.find_path_for_scene(
				scene_index, position, combat_target.position
			)
			if not path.is_empty():
				issue_path(path)
		elif dynamic_occupancy == null:
			issue_move(combat_target.position)
	return false


func _target_is_alive(target: Node2D) -> bool:
	return (
		target != null
		and is_instance_valid(target)
		and target.is_inside_tree()
		and target.has_method("is_combat_alive")
		and bool(target.call("is_combat_alive"))
	)


func _start_one_shot(action: int, groups: Array[Dictionary]) -> void:
	combat_action = action
	action_frame_index = 0
	action_frame_elapsed = 0.0
	action_finished = groups.is_empty()
	was_moving = false
	if groups.size() < 8:
		return
	_apply_action_frame(groups)
	if action == CombatAction.ATTACK and _action_frame_count(groups) == 1:
		_resolve_pending_hit()


func _advance_combat_action(delta: float) -> void:
	if combat_action == CombatAction.RELOAD:
		reload_remaining = maxf(reload_remaining - delta, 0.0)
		if reload_remaining <= 0.0:
			_finish_reload()
		return
	if action_finished:
		return
	var groups := death_groups if combat_action == CombatAction.DEATH else attack_groups
	var frame_count := _action_frame_count(groups)
	if frame_count <= 0:
		action_finished = true
		if combat_action == CombatAction.ATTACK:
			combat_action = CombatAction.NONE
		return
	var group := groups[clampi(animation_group_index, 0, 7)]
	var frame_seconds := animation_frame_seconds(group)
	action_frame_elapsed += delta
	while action_frame_elapsed >= frame_seconds and not action_finished:
		action_frame_elapsed -= frame_seconds
		if action_frame_index >= frame_count - 1:
			action_finished = true
			if combat_action == CombatAction.ATTACK:
				combat_action = CombatAction.NONE
				pending_hit_target = null
				apply_idle_frame()
			return
		action_frame_index += 1
		_apply_action_frame(groups)
		if combat_action == CombatAction.ATTACK and action_frame_index == frame_count - 1:
			_resolve_pending_hit()


func _apply_action_frame(groups: Array[Dictionary]) -> void:
	if groups.size() < 8:
		return
	var group := groups[clampi(animation_group_index, 0, 7)]
	var frames := group.get("frames", []) as Array[Texture2D]
	if frames.is_empty():
		return
	action_frame_index = clampi(action_frame_index, 0, frames.size() - 1)
	sprite_texture = frames[action_frame_index]
	sprite_anchor = group.get("anchor", Vector2.ZERO) as Vector2
	queue_redraw()


func _action_frame_count(groups: Array[Dictionary]) -> int:
	if groups.size() < 8:
		return 0
	var group := groups[clampi(animation_group_index, 0, 7)]
	return (group.get("frames", []) as Array[Texture2D]).size()


func _resolve_pending_hit() -> void:
	if pending_hit_resolved:
		return
	pending_hit_resolved = true
	if not can_attack_target(pending_hit_target):
		return
	var attack_type := int(weapon_profile.get("attack_type", 0))
	if PROJECTILE_PROFILES.is_projectile_attack(attack_type):
		projectile_requested.emit(self, pending_hit_target, weapon_profile.duplicate(true))
		return
	var damage := maxi(int(weapon_profile.get("damage", 1)), 1)
	var burst_count := maxi(int(weapon_profile.get("burst_count", 1)), 1)
	for unused_shot in range(burst_count):
		if not _target_is_alive(pending_hit_target):
			break
		var applied := int(pending_hit_target.call("take_damage", damage, self))
		if applied > 0:
			attack_hit.emit(self, pending_hit_target, attack_type, applied)


func _start_reload() -> bool:
	var magazine_capacity := maxi(int(weapon_profile.get("magazine_capacity", 0)), 0)
	if combat_inventory != null:
		var state: Dictionary = combat_inventory.weapon_state(
			combat_inventory.active_weapon_key()
		)
		magazine_ammo = int(state.get("magazine", 0))
		reserve_ammo = int(state.get("reserve", 0))
	if (
		infinite_ammo
		or magazine_capacity <= 0
		or magazine_ammo >= magazine_capacity
		or reserve_ammo <= 0
	):
		return false
	cancel_path()
	combat_action = CombatAction.RELOAD
	reload_remaining = maxf(float(weapon_profile.get("reload_seconds", 1.5)), 0.05)
	action_finished = false
	_apply_idle_state()
	return true


func _finish_reload() -> void:
	if combat_inventory != null:
		combat_inventory.reload_active_weapon()
		_sync_ammo_from_inventory(false)
	else:
		var magazine_capacity := maxi(int(weapon_profile.get("magazine_capacity", 0)), 0)
		var needed := maxi(magazine_capacity - magazine_ammo, 0)
		var transferred := mini(needed, reserve_ammo)
		magazine_ammo += transferred
		reserve_ammo -= transferred
	combat_action = CombatAction.NONE
	reload_remaining = 0.0
	action_finished = true
	ammo_changed.emit(self, magazine_ammo, reserve_ammo)
	apply_idle_frame()


func _sync_ammo_from_inventory(emit_change: bool) -> void:
	if combat_inventory == null:
		return
	var state: Dictionary = combat_inventory.weapon_state(combat_inventory.active_weapon_key())
	magazine_ammo = int(state.get("magazine", 0))
	reserve_ammo = int(state.get("reserve", 0))
	if emit_change:
		ammo_changed.emit(self, magazine_ammo, reserve_ammo)


func _interrupt_combat_action() -> void:
	if combat_action == CombatAction.DEATH:
		return
	combat_action = CombatAction.NONE
	action_finished = true
	pending_hit_target = null
	pending_hit_resolved = true
	reload_remaining = 0.0


func _die(killer: Node2D) -> void:
	if not is_alive or death_emitted:
		return
	is_alive = false
	selected = false
	clear_combat_target()
	_interrupt_combat_action()
	cancel_path()
	if dynamic_occupancy != null and dynamic_registered and scene_index >= 0:
		dynamic_occupancy.unregister_scene(scene_index)
		dynamic_registered = false
	self_modulate = Color.WHITE
	pending_hit_target = null
	_start_one_shot(CombatAction.DEATH, death_groups)
	death_emitted = true
	died.emit(self, killer)
	queue_redraw()


func _exit_tree() -> void:
	if dynamic_occupancy != null and dynamic_registered and scene_index >= 0:
		dynamic_occupancy.unregister_scene(scene_index)
		dynamic_registered = false


func _apply_idle_state() -> void:
	if not was_moving and animation_frame_index == 0:
		return
	was_moving = false
	animation_frame_index = 0
	animation_elapsed = 0.0
	apply_idle_frame()
	queue_redraw()


static func direction_group_index(direction: Vector2) -> int:
	if direction.is_zero_approx():
		return 7
	var octant := roundi(direction.angle() / (PI / 4.0))
	return posmod(octant + 5, 8)


func set_animation_group(group_index: int) -> void:
	if movement_groups.size() < 8:
		return
	var safe_index := clampi(group_index, 0, 7)
	if animation_group_index != safe_index:
		animation_group_index = safe_index
		animation_frame_index = 0
		animation_elapsed = 0.0
	update_animation_frame()


func advance_animation(delta: float) -> void:
	if movement_groups.size() < 8:
		return
	var group := movement_groups[animation_group_index]
	var frames := group["frames"] as Array[Texture2D]
	if frames.size() <= 1:
		return
	var frame_seconds := animation_frame_seconds(group)
	animation_elapsed += maxf(delta, 0.0)
	while animation_elapsed >= frame_seconds:
		animation_elapsed -= frame_seconds
		animation_frame_index = (animation_frame_index + 1) % frames.size()
	update_animation_frame()


static func animation_frame_seconds(group: Dictionary) -> float:
	return BASE_SPRITE_TICK_SECONDS * maxi(int(group.get("frame_hold_ticks", 1)), 1)


func update_animation_frame() -> void:
	if movement_groups.size() < 8:
		return
	var group := movement_groups[animation_group_index]
	var frames := group["frames"] as Array[Texture2D]
	if frames.is_empty():
		return
	animation_frame_index = clampi(animation_frame_index, 0, frames.size() - 1)
	sprite_texture = frames[animation_frame_index]
	sprite_anchor = group["anchor"] as Vector2


func apply_idle_frame() -> void:
	if idle_groups.size() < 8:
		update_animation_frame()
		return
	var group := idle_groups[animation_group_index]
	var frames := group["frames"] as Array[Texture2D]
	if frames.is_empty():
		return
	sprite_texture = frames[0]
	sprite_anchor = group["anchor"] as Vector2


func _draw() -> void:
	draw_flat_ellipse(Vector2(0.0, 8.0), Vector2(20.0, 10.0), Color(0.0, 0.0, 0.0, 0.35))
	if sprite_texture != null:
		draw_texture(sprite_texture, -sprite_anchor)
	else:
		draw_circle(Vector2.ZERO, 15.0, body_color)
		draw_circle(Vector2(0.0, -12.0), 8.0, body_color.lightened(0.18))
		draw_line(Vector2(-8.0, 1.0), Vector2(11.0, 1.0), Color(0.13, 0.12, 0.09), 4.0)
	if maximum_hit_points > 0 and (selected or current_hit_points < maximum_hit_points):
		var health_ratio := clampf(
			float(current_hit_points) / float(maximum_hit_points), 0.0, 1.0
		)
		draw_rect(Rect2(-18.0, -34.0, 36.0, 5.0), Color(0.08, 0.08, 0.07, 0.85), true)
		draw_rect(
			Rect2(-17.0, -33.0, 34.0 * health_ratio, 3.0),
			Color(0.30, 0.78, 0.30) if health_ratio > 0.35 else Color(0.92, 0.25, 0.18),
			true,
		)
	if selected:
		draw_arc(Vector2.ZERO, 23.0, 0.0, TAU, 40, Color(0.98, 0.84, 0.25), 3.0)
		if position.distance_squared_to(target_position) > 4.0:
			draw_line(Vector2.ZERO, target_position - position, Color(0.98, 0.84, 0.25, 0.65), 1.5)


func draw_flat_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in range(24):
		var angle: float = TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
