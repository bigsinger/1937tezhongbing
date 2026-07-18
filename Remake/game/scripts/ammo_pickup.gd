class_name AmmoPickup
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

signal collected(pickup: Node2D, collector: Node, item_id: int, quantity: int)

const COMBAT_INVENTORY_SCRIPT: Script = preload("res://scripts/combat_inventory.gd")

var ammo_item_id := 0
var quantity := 0
var pickup_label := ""
var consumed := false


func configure(item_id: int, new_quantity: int, world_position: Vector2, label: String = "") -> bool:
	if not COMBAT_INVENTORY_SCRIPT.supports_ammo_item(item_id) or new_quantity <= 0:
		return false
	ammo_item_id = item_id
	quantity = new_quantity
	pickup_label = label
	position = world_position
	consumed = false
	z_index = WORLD_DEPTH.normal_z(position.y, 2)
	queue_redraw()
	return true


func collect_into(inventory: RefCounted, collector: Node = null) -> int:
	if consumed or inventory == null or not inventory.has_method("add_item"):
		return 0
	var accepted := int(inventory.call("add_item", ammo_item_id, quantity))
	if accepted <= 0:
		return 0
	consumed = true
	collected.emit(self, collector, ammo_item_id, accepted)
	if is_inside_tree():
		queue_free()
	return accepted


func _draw() -> void:
	if consumed:
		return
	draw_circle(Vector2.ZERO, 10.0, Color(0.86, 0.66, 0.18, 0.95))
	draw_rect(Rect2(-6.0, -4.0, 12.0, 8.0), Color(0.24, 0.20, 0.13), true)
	draw_line(Vector2(-4.0, 0.0), Vector2(4.0, 0.0), Color(0.95, 0.88, 0.54), 2.0)
