class_name ExplosiveProp
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")
const LEGACY_ROW_SLICE_SPRITE_SCRIPT: Script = preload(
	"res://scripts/legacy_row_slice_sprite.gd"
)
const LEGACY_EXPLOSION_RULES: Script = preload(
	"res://scripts/legacy_explosion_rules.gd"
)

signal damage_taken(prop: Node2D, amount: int, remaining_hit_points: int, attacker: Node2D)
signal explosion_requested(
	prop: Node2D,
	instigator: Node2D,
	world_position: Vector2,
	damage: int,
	horizontal_radius: float,
	vertical_radius: float,
	source_faction_id: int,
)
signal destroyed(prop: Node2D, instigator: Node2D)

const EXPLOSIVE_BEHAVIOR := "explosive_prop"

var database_entry_id := 0
var runtime_actor_type := 0
var scene_index := -1
var profile_key := ""
var original_display_name := ""
var entity_metadata: Dictionary = {}
var faction_id := 0
var max_hit_points := 0
var hit_points := 0
var detonation_hit_points_sentinel := 0
var resolved_action_index := 0
var effect_dispatch_type := 0
var explosion_actor_type := 0
var blast_damage := 0
var blast_horizontal_radius := 0.0
var blast_vertical_radius := 0.0
var alert_radius := 0.0
var special_damage_bands: Array[Dictionary] = []
var has_exploded := false

var _original_sprite: Sprite2D
var _row_slice_renderer: Node2D


func configure(
	profile: Dictionary,
	metadata: Dictionary = {},
	original_texture: Texture2D = null,
	draw_order_profile: Dictionary = {},
) -> bool:
	if (
		String(profile.get("behavior", "")) != EXPLOSIVE_BEHAVIOR
		or int(profile.get("database_entry_id", 0)) <= 0
		or int(profile.get("runtime_actor_type", 0)) != 53
		or int(profile.get("initial_hit_points", 0)) <= 0
		or int(profile.get("detonation_hit_points_sentinel", 0)) <= 0
		or int(profile.get("resolved_action_index", -1)) != 1
		or int(profile.get("effect_dispatch_type", 0)) != 5
	):
		return false
	var requested_explosion_actor_type := int(
		profile.get("explosion_actor_type", 0)
	)
	var explosion_profile: Dictionary = (
		LEGACY_EXPLOSION_RULES.profile_for_actor(
			requested_explosion_actor_type
		)
	)
	if explosion_profile.is_empty():
		return false
	database_entry_id = int(profile["database_entry_id"])
	runtime_actor_type = int(profile["runtime_actor_type"])
	var header_values: Variant = metadata.get("database_header_values", [])
	if header_values is Array and (header_values as Array).size() > 2:
		if int((header_values as Array)[2]) != runtime_actor_type:
			return false
	profile_key = String(profile.get("key", ""))
	original_display_name = String(profile.get("original_display_name", profile_key))
	entity_metadata = metadata.duplicate(true)
	scene_index = int(entity_metadata.get("scene_index", -1))
	faction_id = int(entity_metadata.get("faction_id", 0))
	max_hit_points = int(profile["initial_hit_points"])
	hit_points = max_hit_points
	detonation_hit_points_sentinel = int(
		profile["detonation_hit_points_sentinel"]
	)
	if detonation_hit_points_sentinel != max_hit_points:
		return false
	resolved_action_index = int(profile["resolved_action_index"])
	effect_dispatch_type = int(profile["effect_dispatch_type"])
	explosion_actor_type = requested_explosion_actor_type
	blast_damage = int(explosion_profile["blast_damage"])
	blast_horizontal_radius = float(
		explosion_profile["blast_horizontal_radius"]
	)
	blast_vertical_radius = float(
		explosion_profile["blast_vertical_radius"]
	)
	alert_radius = float(explosion_profile["alert_radius"])
	special_damage_bands.clear()
	for raw_band: Variant in explosion_profile.get(
		"special_damage_bands",
		[],
	) as Array:
		if raw_band is Dictionary:
			special_damage_bands.append(
				(raw_band as Dictionary).duplicate(true)
			)
	if entity_metadata.has("x") and entity_metadata.has("y"):
		position = Vector2(float(entity_metadata["x"]), float(entity_metadata["y"]))
	has_exploded = false
	visible = true
	z_index = WORLD_DEPTH.normal_z(position.y)
	_set_original_texture(original_texture, draw_order_profile)
	queue_redraw()
	return true


func is_combat_alive() -> bool:
	# Actor 53 remains in the original actor table until sub_4551B0 observes
	# HP != 8 and sets +0x1CC. Even a hit that clamps HP to zero therefore
	# remains a pending explosion until this object's own next world tick.
	return not has_exploded


func take_damage(amount: int, attacker: Node2D = null) -> int:
	if has_exploded or amount <= 0:
		return 0
	var applied := mini(amount, hit_points)
	hit_points -= applied
	if applied > 0:
		damage_taken.emit(self, applied, hit_points, attacker)
	queue_redraw()
	return applied


func request_explosion(instigator: Node2D = null) -> bool:
	if has_exploded:
		return false
	has_exploded = true
	hit_points = 0
	explosion_requested.emit(
		self,
		instigator,
		global_position,
		blast_damage,
		blast_horizontal_radius,
		blast_vertical_radius,
		faction_id,
	)
	destroyed.emit(self, instigator)
	visible = false
	queue_redraw()
	if is_inside_tree():
		queue_free()
	return true


func explosion_payload() -> Dictionary:
	return {
		"source": self,
		"world_position": global_position,
		"damage": blast_damage,
		"horizontal_radius": blast_horizontal_radius,
		"vertical_radius": blast_vertical_radius,
		"alert_radius": alert_radius,
		"special_damage_bands": special_damage_bands.duplicate(true),
		"runtime_actor_type": runtime_actor_type,
		"explosion_actor_type": explosion_actor_type,
		"source_faction_id": faction_id,
		"database_entry_id": database_entry_id,
		"scene_index": scene_index,
	}


func advance_world_ticks(ticks: int = 1) -> void:
	for unused_tick: int in range(maxi(ticks, 0)):
		if has_exploded:
			return
		if hit_points != detonation_hit_points_sentinel:
			# sub_4551B0 creates actor 62 without retaining the attacker pointer.
			request_explosion()
			return


func restore_runtime_state(restored_hit_points: int) -> bool:
	if has_exploded:
		return false
	hit_points = clampi(restored_hit_points, 0, max_hit_points)
	queue_redraw()
	return true


func _physics_process(_delta: float) -> void:
	advance_world_ticks(1)


func has_original_texture() -> bool:
	return _original_sprite != null and _original_sprite.texture != null


func _set_original_texture(
	texture: Texture2D,
	draw_order_profile: Dictionary = {},
) -> void:
	if _original_sprite == null:
		_original_sprite = Sprite2D.new()
		_original_sprite.name = "OriginalSprite"
		add_child(_original_sprite)
	_original_sprite.texture = texture
	_original_sprite.visible = texture != null and not has_exploded
	if texture != null:
		var anchor := _entity_sprite_anchor(texture)
		_original_sprite.offset = texture.get_size() * 0.5 - anchor
		if _apply_draw_order_profile(
			texture,
			anchor,
			draw_order_profile,
		):
			_original_sprite.visible = false


func _apply_draw_order_profile(
	texture: Texture2D,
	anchor: Vector2,
	draw_order_profile: Dictionary,
) -> bool:
	if draw_order_profile.is_empty():
		return false
	var frame_size: Variant = draw_order_profile.get(
		"frame_size",
		Vector2i.ZERO,
	)
	var row_lookup: Variant = draw_order_profile.get(
		"draw_order_row_lookup",
		[],
	)
	if (
		not frame_size is Vector2i
		or frame_size
			!= Vector2i(
				int(round(texture.get_width())),
				int(round(texture.get_height())),
			)
		or not row_lookup is Array
		or (row_lookup as Array).is_empty()
	):
		return false
	var reference_y := float(
		entity_metadata.get("reference_y", entity_metadata.get("y", position.y))
	)
	if _rows_are_uniform(row_lookup as Array):
		z_index = WORLD_DEPTH.normal_z(
			reference_y - anchor.y + float((row_lookup as Array)[0])
		)
		return false
	if _row_slice_renderer == null or not is_instance_valid(_row_slice_renderer):
		_row_slice_renderer = LEGACY_ROW_SLICE_SPRITE_SCRIPT.new()
		_row_slice_renderer.name = "OriginalRowSlices"
		add_child(_row_slice_renderer)
	_row_slice_renderer.visible = true
	return bool(
		_row_slice_renderer.call(
			"configure",
			texture,
			anchor,
			reference_y,
			row_lookup,
		)
	)


static func _rows_are_uniform(rows: Array) -> bool:
	if rows.is_empty():
		return false
	var first: Variant = rows[0]
	if not first is int and not first is float:
		return false
	for row: Variant in rows:
		if (
			(not row is int and not row is float)
			or float(row) != float(first)
		):
			return false
	return true


func _entity_sprite_anchor(texture: Texture2D) -> Vector2:
	var value: Variant = entity_metadata.get("sprite_anchor", {})
	if value is Dictionary:
		var anchor := value as Dictionary
		if anchor.has("x") and anchor.has("y"):
			return Vector2(float(anchor["x"]), float(anchor["y"]))
	return texture.get_size() * 0.5


func _draw() -> void:
	if has_exploded:
		if _original_sprite != null:
			_original_sprite.visible = false
		if _row_slice_renderer != null:
			_row_slice_renderer.visible = false
		return
	if has_original_texture():
		return
	draw_rect(Rect2(-9.0, -14.0, 18.0, 28.0), Color(0.45, 0.15, 0.08), true)
	draw_line(Vector2(-8.0, -6.0), Vector2(8.0, -6.0), Color(0.82, 0.42, 0.14), 2.0)
	draw_line(Vector2(-8.0, 6.0), Vector2(8.0, 6.0), Color(0.82, 0.42, 0.14), 2.0)
	var health_ratio := float(hit_points) / float(maxi(max_hit_points, 1))
	draw_rect(Rect2(-9.0, -19.0, 18.0, 3.0), Color(0.12, 0.08, 0.06), true)
	draw_rect(Rect2(-9.0, -19.0, 18.0 * health_ratio, 3.0), Color(0.94, 0.62, 0.16), true)
