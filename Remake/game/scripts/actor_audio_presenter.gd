class_name ActorAudioPresenter
extends RefCounted

const WORLD_AUDIO_SPATIALIZER := preload("res://scripts/world_audio_spatializer.gd")


func mix_for_source(source: Vector2, camera_world_rect: Rect2) -> Dictionary:
	var mix := WORLD_AUDIO_SPATIALIZER.mix_for_source(source, camera_world_rect)
	var center := camera_world_rect.get_center()
	var half_width := maxf(camera_world_rect.size.x * 0.5, 1.0)
	mix["pan"] = clampf((source.x - center.x) / half_width, -1.0, 1.0)
	return mix


func volume_db_for_source(source: Vector2, camera_world_rect: Rect2) -> float:
	return WORLD_AUDIO_SPATIALIZER.volume_db_for_source(
		source,
		camera_world_rect,
	)
