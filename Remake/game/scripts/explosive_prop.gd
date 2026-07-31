class_name ExplosiveProp
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")
const LEGACY_ROW_SLICE_SPRITE_SCRIPT: Script = preload(
	"res://scripts/legacy_row_slice_sprite.gd"
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
var blast_damage := 0
var blast_horizontal_radius := 0.0
var blast_vertical_radius := 0.0
var destroyed_visual_seconds := 0.0
var has_exploded := false
var resolved_visual_remaining := 0.0

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
		or int(profile.get("hit_points", 0)) <= 0
		or int(profile.get("blast_damage", 0)) <= 0
		or float(profile.get("blast_horizontal_radius", 0.0)) <= 0.0
		or float(profile.get("blast_vertical_radius", 0.0)) <= 0.0
	):
		return false
	database_entry_id = int(profile["database_entry_id"])
	runtime_actor_type = 0
	var header_values: Variant = metadata.get("database_header_values", [])
	if header_values is Array and (header_values as Array).size() > 2:
		runtime_actor_type = int((header_values as Array)[2])
	profile_key = String(profile.get("key", ""))
	original_display_name = String(profile.get("original_display_name", profile_key))
	entity_metadata = metadata.duplicate(true)
	scene_index = int(entity_metadata.get("scene_index", -1))
	faction_id = int(entity_metadata.get("faction_id", 0))
	max_hit_points = int(profile["hit_points"])
	hit_points = max_hit_points
	blast_damage = int(profile["blast_damage"])
	blast_horizontal_radius = float(profile["blast_horizontal_radius"])
	blast_vertical_radius = float(profile["blast_vertical_radius"])
	destroyed_visual_seconds = maxf(float(profile.get("destroyed_visual_seconds", 0.12)), 0.0)
	if entity_metadata.has("x") and entity_metadata.has("y"):
		position = Vector2(float(entity_metadata["x"]), float(entity_metadata["y"]))
	has_exploded = false
	resolved_visual_remaining = 0.0
	visible = true
	z_index = WORLD_DEPTH.normal_z(position.y)
	_set_original_texture(original_texture, draw_order_profile)
	queue_redraw()
	return true


func is_combat_alive() -> bool:
	return not has_exploded and hit_points > 0


func take_damage(amount: int, attacker: Node2D = null) -> int:
	if has_exploded or amount <= 0:
		return 0
	var applied := mini(amount, hit_points)
	hit_points -= applied
	if applied > 0:
		damage_taken.emit(self, applied, hit_points, attacker)
	if hit_points <= 0:
		request_explosion(attacker)
	queue_redraw()
	return applied


func request_explosion(instigator: Node2D = null) -> bool:
	if has_exploded:
		return false
	has_exploded = true
	hit_points = 0
	resolved_visual_remaining = destroyed_visual_seconds
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
	queue_redraw()
	return true


func explosion_payload() -> Dictionary:
	return {
		"source": self,
		"world_position": global_position,
		"damage": blast_damage,
		"horizontal_radius": blast_horizontal_radius,
		"vertical_radius": blast_vertical_radius,
		"source_faction_id": faction_id,
		"database_entry_id": database_entry_id,
		"scene_index": scene_index,
	}


func _physics_process(delta: float) -> void:
	if not has_exploded:
		return
	resolved_visual_remaining = maxf(resolved_visual_remaining - maxf(delta, 0.0), 0.0)
	if resolved_visual_remaining <= 0.0 and is_inside_tree():
		queue_free()


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
		_draw_ellipse(
			Vector2(blast_horizontal_radius, blast_vertical_radius),
			Color(1.0, 0.39, 0.08, 0.34),
		)
		return
	if has_original_texture():
		return
	draw_rect(Rect2(-9.0, -14.0, 18.0, 28.0), Color(0.45, 0.15, 0.08), true)
	draw_line(Vector2(-8.0, -6.0), Vector2(8.0, -6.0), Color(0.82, 0.42, 0.14), 2.0)
	draw_line(Vector2(-8.0, 6.0), Vector2(8.0, 6.0), Color(0.82, 0.42, 0.14), 2.0)
	var health_ratio := float(hit_points) / float(maxi(max_hit_points, 1))
	draw_rect(Rect2(-9.0, -19.0, 18.0, 3.0), Color(0.12, 0.08, 0.06), true)
	draw_rect(Rect2(-9.0, -19.0, 18.0 * health_ratio, 3.0), Color(0.94, 0.62, 0.16), true)


func _draw_ellipse(radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in range(32):
		var angle := TAU * float(index) / 32.0
		points.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
