class_name LevelRuntimeFactory
extends RefCounted

const LEGACY_DOOR_SCRIPT: Script = preload("res://scripts/legacy_door.gd")
const MISSION_PICKUP_SCRIPT: Script = preload("res://scripts/mission_pickup.gd")


func native_squad_specifications(playable_entities: Dictionary) -> Array[Dictionary]:
	var names := playable_entities.keys()
	names.sort()
	var specifications: Array[Dictionary] = []
	for name_value: Variant in names:
		specifications.append({"name": str(name_value), "color": Color("79a8c9")})
	return specifications


func entity_world_position(entity: Dictionary) -> Vector2:
	return Vector2(
		float(entity.get("reference_x", entity.get("x", 0.0))),
		float(entity.get("reference_y", entity.get("y", 0.0))),
	)


func placeholder_texture(role: String, size: Vector2i = Vector2i(24, 34)) -> Texture2D:
	var color := Color("8b8b78")
	match role:
		"player":
			color = Color("6f9dbe")
		"enemy":
			color = Color("b45f55")
		"ambient", "escort":
			color = Color("b7a56f")
		"door":
			color = Color("805f3f")
		"pickup":
			color = Color("d5ae4b")
	var image := Image.create(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	if role == "door":
		image.fill_rect(
			Rect2i(2, 2, maxi(size.x - 4, 1), maxi(size.y - 2, 1)),
			color,
		)
		image.fill_rect(
			Rect2i(maxi(size.x - 7, 1), maxi(size.y / 2, 1), 3, 3),
			color.lightened(0.45),
		)
		return ImageTexture.create_from_image(image)
	if role == "pickup":
		var center := Vector2i(size.x / 2, size.y / 2)
		image.fill_rect(Rect2i(center.x - 6, center.y - 4, 12, 8), color)
		image.fill_rect(
			Rect2i(center.x - 4, center.y - 6, 8, 2),
			color.lightened(0.3),
		)
		return ImageTexture.create_from_image(image)
	image.fill_rect(Rect2i(8, 2, 8, 8), color.lightened(0.18))
	image.fill_rect(Rect2i(5, 10, 14, 16), color)
	image.fill_rect(Rect2i(6, 26, 5, 8), color.darkened(0.15))
	image.fill_rect(Rect2i(13, 26, 5, 8), color.darkened(0.15))
	return ImageTexture.create_from_image(image)


func native_open_door_texture(closed_texture: Texture2D) -> Texture2D:
	var width := 24
	var height := 34
	if closed_texture != null:
		width = maxi(roundi(closed_texture.get_width()), 1)
		height = maxi(roundi(closed_texture.get_height()), 1)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	# An open door keeps a narrow jamb visible while its transparent centre
	# releases both authored movement and sight cells.
	var jamb := Color("805f3f")
	image.fill_rect(Rect2i(0, 0, mini(3, width), height), jamb)
	image.fill_rect(Rect2i(0, 0, width, mini(2, height)), jamb.lightened(0.12))
	return ImageTexture.create_from_image(image)


func create_native_door(
	entity: Dictionary,
	closed_texture: Texture2D,
	z_index: int,
) -> Node2D:
	if closed_texture == null:
		return null
	var interaction := entity.get("native_interaction", {}) as Dictionary
	if str(interaction.get("kind", "")) != "door":
		return null
	var profile := {
		"name": str(entity.get("display_name", "Door")),
		"open_gfl_index": 0,
		"starts_open": bool(interaction.get("starts_open", false)),
		"locked_open": bool(interaction.get("locked_open", false)),
		"closed_anchor": entity.get(
			"sprite_anchor",
			closed_texture.get_size() * 0.5,
		),
		"open_anchor": entity.get(
			"sprite_anchor",
			closed_texture.get_size() * 0.5,
		),
	}
	var door: Node2D = LEGACY_DOOR_SCRIPT.new()
	if not bool(door.call(
		"configure",
		entity,
		profile,
		closed_texture,
		native_open_door_texture(closed_texture),
		z_index,
		{},
		{},
	)):
		door.free()
		return null
	return door


func create_native_pickup(
	entity: Dictionary,
	texture: Texture2D,
) -> Node2D:
	var interaction := entity.get("native_interaction", {}) as Dictionary
	if str(interaction.get("kind", "")) != "pickup":
		return null
	var pickup: Node2D = MISSION_PICKUP_SCRIPT.new()
	pickup.call(
		"configure",
		interaction,
		entity_world_position(entity),
		texture,
	)
	return pickup
