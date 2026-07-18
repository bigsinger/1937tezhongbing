class_name ExplosiveProp
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

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


func configure(
	profile: Dictionary,
	metadata: Dictionary = {},
	original_texture: Texture2D = null,
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
	z_index = WORLD_DEPTH.normal_z(position.y, 1)
	_set_original_texture(original_texture)
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


func _set_original_texture(texture: Texture2D) -> void:
	if _original_sprite == null:
		_original_sprite = Sprite2D.new()
		_original_sprite.name = "OriginalSprite"
		add_child(_original_sprite)
	_original_sprite.texture = texture
	_original_sprite.visible = texture != null and not has_exploded


func _draw() -> void:
	if has_exploded:
		if _original_sprite != null:
			_original_sprite.visible = false
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
