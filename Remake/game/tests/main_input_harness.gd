# Test fixture only: instantiate this class from a SceneTree test. It deliberately
# inherits Main and therefore must never be passed to Godot's --script option.
extends "res://scripts/main.gd"


func _ready() -> void:
	# Tests opt into individual Main subsystems without loading a formal level.
	pass
