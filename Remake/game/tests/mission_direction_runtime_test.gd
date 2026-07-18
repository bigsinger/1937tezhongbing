extends SceneTree

const MISSION_DATA_SCRIPT: Script = preload("res://scripts/mission_data.gd")
const DIRECTION_DATA_SCRIPT: Script = preload("res://scripts/mission_direction_data.gd")
const DIRECTION_RUNTIME_SCRIPT: Script = preload("res://scripts/mission_direction_runtime.gd")
const AI_COORDINATOR_SCRIPT: Script = preload("res://scripts/mission_ai_coordinator.gd")
const ENEMY_UNIT_SCRIPT: Script = preload("res://scripts/enemy_unit.gd")

var checks := 0


class FakeMediaDirector extends Node:
	var sequences: Array[String] = []
	var line_counts: Array[int] = []

	func start_dialogue(sequence_id: String, lines: Array) -> bool:
		sequences.append(sequence_id)
		line_counts.append(lines.size())
		return true


class QueuedMediaDirector extends Node:
	signal dialogue_finished(sequence_id: String, skipped: bool)
	var dialogue_sequence_id := ""
	var sequences: Array[String] = []

	func start_dialogue(sequence_id: String, _lines: Array) -> bool:
		if not dialogue_sequence_id.is_empty():
			return false
		dialogue_sequence_id = sequence_id
		sequences.append(sequence_id)
		return true

	func finish() -> void:
		var finished := dialogue_sequence_id
		dialogue_sequence_id = ""
		dialogue_finished.emit(finished, false)


class FakeEnemy extends Node2D:
	var scene_index := -1
	var is_alive := true
	var current_hit_points := 8
	var maximum_hit_points := 8
	var move_speed := 100.0
	var attack_recheck_seconds := 0.5
	var weapon_profile: Dictionary = {"damage": 10}
	var sense_profile: Dictionary = {"horizontal_radius": 100.0, "vertical_radius": 50.0}
	var alert_count := 0
	var last_alert_position := Vector2.ZERO
	var current_target: Node2D
	var configured_coordinator: Node
	var configured_values: Dictionary = {}
	var configured_cooperation: Dictionary = {}
	var applied_posture := ""
	var applied_tags: Array[String] = []

	func receive_alert(_target: Node2D, world_position: Vector2) -> bool:
		alert_count += 1
		last_alert_position = world_position
		return true

	func configure_editorial_ai(
		coordinator: Node,
		values: Dictionary,
		cooperation: Dictionary,
	) -> void:
		configured_coordinator = coordinator
		configured_values = values.duplicate(true)
		configured_cooperation = cooperation.duplicate(true)

	func apply_editorial_ai_posture(posture: String, tags: Array[String]) -> void:
		applied_posture = posture
		applied_tags = tags.duplicate()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var mission_catalog: Dictionary = MISSION_DATA_SCRIPT.load_catalog()
	var direction_catalog: Dictionary = DIRECTION_DATA_SCRIPT.load_catalog()
	expect(not mission_catalog.is_empty(), "recovered mission catalog loads", failures)
	expect(not direction_catalog.is_empty(), "mission direction catalog loads", failures)
	expect(
		DIRECTION_DATA_SCRIPT.validate_catalog(direction_catalog, mission_catalog).is_empty(),
		"all mission direction data cross-validates against recovered mission ids/objectives/bindings",
		failures,
	)
	expect(int(direction_catalog.get("mission_count", 0)) == 12, "all twelve levels are directed", failures)
	expect(
		not bool((direction_catalog.get("provenance", {}) as Dictionary).get("original_dialogue_claimed", true)),
		"catalog explicitly declines to claim an unverified original transcript",
		failures,
	)

	var expected_titles: Array[String] = [
		"营救行动", "奇袭火车站", "劫狱", "铁路桥", "火烧粮仓", "大闹寒江镇",
		"惩罚", "脱困", "暗战矿坑", "夺宝奇兵", "血色渡口", "破袭机场",
	]
	var previous_health := 0.0
	var previous_damage := 0.0
	var previous_reaction := INF
	var total_beats := 0
	var total_lines := 0
	for index: int in range(12):
		var mission_id := "m%03d" % index
		var plan: Dictionary = DIRECTION_DATA_SCRIPT.load_mission_plan(mission_id)
		expect(not plan.is_empty(), "%s plan is individually addressable" % mission_id, failures)
		expect(str(plan.get("title", "")) == expected_titles[index], "%s keeps the recovered title" % mission_id, failures)
		var difficulty := plan.get("difficulty", {}) as Dictionary
		var cooperation := plan.get("ai_cooperation", {}) as Dictionary
		var health := float(difficulty.get("enemy_health_multiplier", 0.0))
		var damage := float(difficulty.get("enemy_damage_multiplier", 0.0))
		var reaction := float(difficulty.get("reaction_time_multiplier", INF))
		expect(health >= previous_health, "%s enemy-health curve does not regress" % mission_id, failures)
		expect(damage >= previous_damage, "%s enemy-damage curve does not regress" % mission_id, failures)
		expect(reaction <= previous_reaction, "%s reaction-time curve becomes no easier" % mission_id, failures)
		previous_health = health
		previous_damage = damage
		previous_reaction = reaction
		expect(
			str(difficulty.get("source_status", "")) == "remake_editorial"
			and str(cooperation.get("source_status", "")) == "remake_editorial",
			"%s tuning does not masquerade as recovered original values" % mission_id,
			failures,
		)
		expect(
			(cooperation.get("tags", []) as Array).size() >= 2,
			"%s declares level-specific AI cooperation roles" % mission_id,
			failures,
		)
		var coverage := {"dialogue": false, "camera": false, "tutorial": false, "ai": false}
		var has_start := false
		var has_victory := false
		for raw_beat: Variant in plan.get("beats", []) as Array:
			var beat := raw_beat as Dictionary
			total_beats += 1
			var trigger := beat.get("trigger", {}) as Dictionary
			has_start = has_start or str(trigger.get("event", "")) == "mission_started"
			has_victory = has_victory or str(trigger.get("event", "")) == "victory"
			if beat.has("dialogue"):
				coverage["dialogue"] = true
				var dialogue := beat["dialogue"] as Dictionary
				total_lines += (dialogue.get("lines", []) as Array).size()
				expect(
					str(dialogue.get("source_status", "")) == "remake_editorial",
					"%s dialogue is explicitly editorial" % mission_id,
					failures,
				)
			if beat.has("camera"):
				coverage["camera"] = true
				var camera := beat["camera"] as Dictionary
				if str(camera.get("mode", "")) == "focus_binding":
					expect(
						str(camera.get("source_status", "")) == "recovered_scene_binding",
						"%s focus camera discloses its recovered binding source" % mission_id,
						failures,
					)
			if beat.has("tutorial"):
				coverage["tutorial"] = true
			if beat.has("ai_directive"):
				coverage["ai"] = true
		expect(has_start and has_victory, "%s has opening and completion rhythms" % mission_id, failures)
		expect(
			bool(coverage["dialogue"])
			and bool(coverage["camera"])
			and bool(coverage["tutorial"])
			and bool(coverage["ai"]),
			"%s covers dialogue, camera, tutorial and AI direction" % mission_id,
			failures,
		)
	expect(total_beats >= 40, "twelve levels provide more than forty authored beats", failures)
	expect(total_lines >= total_beats, "each authored beat carries at least one dialogue line", failures)

	var fake_media := FakeMediaDirector.new()
	root.add_child(fake_media)
	var runtime: Node = DIRECTION_RUNTIME_SCRIPT.new()
	root.add_child(runtime)
	var difficulty_events: Array[Dictionary] = []
	var cooperation_events: Array[Dictionary] = []
	var camera_beats: Array[String] = []
	var dialogue_sequences: Array[String] = []
	var tutorial_events: Array[String] = []
	var ai_beats: Array[String] = []
	runtime.difficulty_profile_requested.connect(func(profile: Dictionary) -> void: difficulty_events.append(profile))
	runtime.ai_cooperation_requested.connect(func(profile: Dictionary) -> void: cooperation_events.append(profile))
	runtime.camera_requested.connect(func(beat_id: String, _camera: Dictionary) -> void: camera_beats.append(beat_id))
	runtime.dialogue_requested.connect(func(sequence_id: String, _lines: Array, _source: String) -> void: dialogue_sequences.append(sequence_id))
	runtime.tutorial_requested.connect(func(tutorial_id: String, _tutorial: Dictionary) -> void: tutorial_events.append(tutorial_id))
	runtime.ai_directive_requested.connect(func(beat_id: String, _directive: Dictionary) -> void: ai_beats.append(beat_id))
	expect(bool(runtime.call("configure_for_mission", "m000", fake_media, "normal")), "m000 runtime configures", failures)
	expect(bool(runtime.call("start")), "mission direction starts once", failures)
	expect(not bool(runtime.call("start")), "mission direction cannot double-start", failures)
	expect(
		difficulty_events.size() == 1 and cooperation_events.size() == 1,
		"start emits one difficulty and one AI cooperation profile",
		failures,
	)
	expect(bool(runtime.call("is_beat_fired", "intro")), "opening beat fires at mission start", failures)
	expect(
		fake_media.sequences == ["m000_intro_editorial"]
		and fake_media.line_counts == [2]
		and dialogue_sequences == ["m000_intro_editorial"],
		"editorial opening dialogue reaches both signal and attached media director",
		failures,
	)
	expect(
		camera_beats == ["intro"] and tutorial_events == ["m000_move"] and ai_beats == ["intro"],
		"opening beat emits camera, tutorial and AI commands",
		failures,
	)
	var gated: Array[String] = runtime.call(
		"publish_event", "objective_completed", {"objective_id": "rescue_pengxin"}
	)
	expect(gated.is_empty(), "objective beat waits for its tutorial gate", failures)
	expect(not bool(runtime.call("is_beat_fired", "first_rescue")), "gated beat remains pending", failures)
	var completed_tutorials: Array[String] = runtime.call("report_tutorial_action", "move_order")
	expect(completed_tutorials == ["m000_move"], "observed action completes the tutorial", failures)
	expect(bool(runtime.call("is_beat_fired", "first_rescue")), "durable objective event replays after gate completion", failures)
	var dialogue_count_after_replay := dialogue_sequences.size()
	runtime.call("publish_event", "objective_completed", {"objective_id": "rescue_pengxin"})
	expect(
		dialogue_sequences.size() == dialogue_count_after_replay,
		"duplicate objective callbacks cannot replay a one-shot beat",
		failures,
	)
	var victory_beats: Array[String] = runtime.call("publish_event", "victory")
	expect(victory_beats == ["victory"], "victory dispatches its completion beat", failures)
	var rejected_elapsed: Array[String] = runtime.call("publish_event", "elapsed_seconds", {})
	expect(
		rejected_elapsed.is_empty()
		and str(runtime.get("last_error")).contains("unsupported"),
		"elapsed triggers are owned by advance_time rather than publish_event",
		failures,
	)
	var queued_media := QueuedMediaDirector.new()
	root.add_child(queued_media)
	var queued_runtime: Node = DIRECTION_RUNTIME_SCRIPT.new()
	root.add_child(queued_runtime)
	var queued_camera_beats: Array[String] = []
	queued_runtime.camera_requested.connect(
		func(beat_id: String, _camera: Dictionary) -> void:
			queued_camera_beats.append(beat_id)
	)
	expect(
		bool(queued_runtime.call("configure_for_mission", "m000", queued_media))
		and bool(queued_runtime.call("start")),
		"runtime attaches to a completion-aware media director",
		failures,
	)
	queued_runtime.call("publish_event", "objective_completed", {"objective_id": "rescue_pengxin"})
	queued_runtime.call("report_tutorial_action", "move_order")
	queued_runtime.call("publish_event", "victory")
	expect(
		bool(queued_runtime.call(
			"queue_external_dialogue",
			"legacy_followup",
			[{"speaker": "任务提示", "text": "legacy follow-up"}],
		)),
		"legacy mission dialogue can join the same deterministic presentation queue",
		failures,
	)
	expect(
		queued_media.sequences == ["m000_intro_editorial"]
		and queued_camera_beats == ["intro"],
		"same-frame objective/victory dialogue and cameras wait behind the active opening",
		failures,
	)
	queued_media.finish()
	await process_frame
	expect(
		queued_media.sequences == ["m000_intro_editorial", "m000_first_rescue_editorial"]
		and queued_camera_beats == ["intro", "first_rescue"],
		"queued objective camera starts with its dialogue after the opening finishes",
		failures,
	)
	queued_media.finish()
	await process_frame
	expect(
		queued_media.sequences == [
			"m000_intro_editorial", "m000_first_rescue_editorial", "m000_victory_editorial"
		]
		and queued_camera_beats == ["intro", "first_rescue", "victory"],
		"victory dialogue and camera remain ordered after the objective presentation",
		failures,
	)
	queued_media.finish()
	await process_frame
	expect(
		queued_media.sequences == [
			"m000_intro_editorial",
			"m000_first_rescue_editorial",
			"m000_victory_editorial",
			"legacy_followup",
		]
		and queued_camera_beats == ["intro", "first_rescue", "victory"],
		"legacy follow-up waits behind director dialogue without cancelling any matched camera",
		failures,
	)
	queued_media.finish()
	await process_frame
	var replay_media := QueuedMediaDirector.new()
	root.add_child(replay_media)
	var replay_runtime: Node = DIRECTION_RUNTIME_SCRIPT.new()
	root.add_child(replay_runtime)
	var replay_camera_beats: Array[String] = []
	replay_runtime.camera_requested.connect(
		func(beat_id: String, _camera: Dictionary) -> void:
			replay_camera_beats.append(beat_id)
	)
	expect(
		bool(replay_runtime.call("configure_for_mission", "m000", replay_media))
		and bool(replay_runtime.call("restore_state", queued_runtime.call("capture_state")))
		and bool(replay_runtime.call("replay_fired_beat_presentation", "victory")),
		"an interrupted victory save can rebuild only its already-fired presentation",
		failures,
	)
	expect(
		replay_media.sequences == ["m000_victory_editorial"]
		and replay_camera_beats == ["victory"],
		"victory presentation replay restores its dialogue and camera without replaying prior beats",
		failures,
	)
	replay_media.finish()
	await process_frame

	var normal_profile: Dictionary = runtime.call("difficulty_profile")
	var easy_profile: Dictionary = DIRECTION_DATA_SCRIPT.difficulty_for_mode(
		(runtime.get("mission_plan") as Dictionary).get("difficulty", {}) as Dictionary, "easy"
	)
	var hard_profile: Dictionary = DIRECTION_DATA_SCRIPT.difficulty_for_mode(
		(runtime.get("mission_plan") as Dictionary).get("difficulty", {}) as Dictionary, "hard"
	)
	expect(
		float(easy_profile["enemy_damage_multiplier"])
		< float(normal_profile["enemy_damage_multiplier"])
		and float(hard_profile["enemy_damage_multiplier"])
		> float(normal_profile["enemy_damage_multiplier"]),
		"global modes scale level-authored damage around normal",
		failures,
	)
	expect(
		float(easy_profile["reaction_time_multiplier"])
		> float(normal_profile["reaction_time_multiplier"])
		and float(hard_profile["reaction_time_multiplier"])
		< float(normal_profile["reaction_time_multiplier"]),
		"reaction-time scaling correctly inverts the lethal multiplier",
		failures,
	)
	var normal_scaled: Dictionary = DIRECTION_DATA_SCRIPT.apply_enemy_scalars(
		8, 10.0, 0.5, normal_profile
	)
	var scaled: Dictionary = DIRECTION_DATA_SCRIPT.apply_enemy_scalars(8, 10.0, 0.5, hard_profile)
	expect(
		int(scaled["health"]) >= int(normal_scaled["health"])
		and float(scaled["damage"]) > float(normal_scaled["damage"])
		and float(scaled["reaction_seconds"]) < float(normal_scaled["reaction_seconds"]),
		"enemy scalar helper produces directly consumable runtime values",
		failures,
	)

	var timed_runtime: Node = DIRECTION_RUNTIME_SCRIPT.new()
	root.add_child(timed_runtime)
	expect(bool(timed_runtime.call("configure_for_mission", "m010")), "m010 runtime configures", failures)
	timed_runtime.call("start")
	var before_gate: Array[String] = timed_runtime.call("advance_time", 2700.0)
	expect(before_gate.is_empty(), "timed warning also respects its tutorial gate", failures)
	expect(
		timed_runtime.call("report_tutorial_action", "issue_split_orders") == ["m010_split_squad"],
		"m010 split-order tutorial completes from its observed action",
		failures,
	)
	expect(bool(timed_runtime.call("is_beat_fired", "time_warning")), "elapsed beat replays when its gate opens", failures)
	var snapshot: Dictionary = timed_runtime.call("capture_state")
	var restored: Node = DIRECTION_RUNTIME_SCRIPT.new()
	root.add_child(restored)
	expect(bool(restored.call("configure_for_mission", "m010")), "restore target configures", failures)
	expect(bool(restored.call("restore_state", snapshot)), "direction state restores", failures)
	expect(
		bool(restored.call("is_beat_fired", "intro"))
		and bool(restored.call("is_beat_fired", "time_warning"))
		and bool(restored.call("is_tutorial_complete", "m010_split_squad")),
		"save restore preserves beats, tutorial gate and elapsed direction state",
		failures,
	)
	expect(
		restored.call("publish_event", "victory") == ["victory"],
		"a restored mission can continue to its remaining beat",
		failures,
	)
	var bad_snapshot := snapshot.duplicate(true) as Dictionary
	bad_snapshot["fired_beats"] = ["not_a_beat"]
	expect(not bool(restored.call("restore_state", bad_snapshot)), "unknown saved beat is rejected", failures)

	var ai_runtime: Node = DIRECTION_RUNTIME_SCRIPT.new()
	root.add_child(ai_runtime)
	expect(bool(ai_runtime.call("configure_for_mission", "m011")), "final-level tuning runtime configures", failures)
	var coordinator: Node = AI_COORDINATOR_SCRIPT.new()
	root.add_child(coordinator)
	var fake_target := Node2D.new()
	fake_target.position = Vector2(64.0, 0.0)
	root.add_child(fake_target)
	var fake_enemies: Array[Node2D] = []
	for index: int in range(5):
		var enemy := FakeEnemy.new()
		enemy.scene_index = 100 + index
		enemy.position = Vector2(float(index * 30), 0.0)
		root.add_child(enemy)
		fake_enemies.append(enemy)
	expect(
		bool(coordinator.call(
			"configure",
			ai_runtime.call("difficulty_profile"),
			ai_runtime.call("ai_cooperation_profile"),
			fake_enemies,
		)),
		"AI coordinator accepts a level-authored profile and enemy registry",
		failures,
	)
	var first_enemy := fake_enemies[0] as FakeEnemy
	expect(
		first_enemy.maximum_hit_points == 9
		and first_enemy.current_hit_points == 9
		and first_enemy.weapon_profile["damage"] == 11
		and first_enemy.move_speed > 100.0
		and first_enemy.attack_recheck_seconds < 0.5,
		"final-level difficulty is applied to health, damage, patrol speed and reaction time",
		failures,
	)
	expect(
		float(first_enemy.sense_profile["horizontal_radius"]) > 100.0
		and float(first_enemy.sense_profile["vertical_radius"]) > 50.0,
		"shared-alert tuning scales both isometric sense radii",
		failures,
	)
	expect(
		first_enemy.configured_coordinator == coordinator
		and is_equal_approx(float(first_enemy.configured_values["aim_error_multiplier"]), 0.89)
		and is_equal_approx(float(first_enemy.configured_values["reaction_time_multiplier"]), 0.86)
		and is_equal_approx(float(first_enemy.configured_cooperation["regroup_seconds"]), 2.3),
		"aim error, durable reaction scaling and regroup timing reach each enemy consumer",
		failures,
	)
	var selected_alerts: Array[int] = coordinator.call(
		"queue_shared_alert", fake_enemies[0], fake_target, Vector2.ZERO, 200.0
	)
	expect(
		selected_alerts == [101, 102, 103],
		"cooperation alert selects the nearest deterministic search group and excludes source",
		failures,
	)
	expect(int(coordinator.call("advance_time", 0.10)) == 0, "shared alert honors its authored delay", failures)
	expect(int(coordinator.call("advance_time", 0.20)) == 3, "shared alert reaches the selected group after delay", failures)
	expect(
		(fake_enemies[1] as FakeEnemy).alert_count == 1
		and (fake_enemies[2] as FakeEnemy).alert_count == 1
		and (fake_enemies[3] as FakeEnemy).alert_count == 1
		and (fake_enemies[4] as FakeEnemy).alert_count == 0,
		"only the bounded AI cooperation group receives the propagated alert",
		failures,
	)
	var selected_attackers: Array[Node2D] = coordinator.call("select_attackers", fake_target)
	expect(
		selected_attackers.size() == 4
		and int(selected_attackers[0].get("scene_index")) == 102,
		"simultaneous attackers are distance ordered and capped by mission difficulty",
		failures,
	)
	for enemy: Node2D in fake_enemies:
		enemy.set("current_target", fake_target)
	expect(
		bool(coordinator.call("request_attack_permission", fake_enemies[2], fake_target))
		and bool(coordinator.call("request_attack_permission", fake_enemies[4], fake_target))
		and not bool(coordinator.call("request_attack_permission", fake_enemies[0], fake_target)),
		"ordinary autonomous attack commits share the same nearest-four global slot cap",
		failures,
	)
	var reinforcement_counts: Array[int] = []
	var reached_triggers: Array[String] = []
	coordinator.reinforcement_requested.connect(
		func(count: int, _reason: String) -> void: reinforcement_counts.append(count)
	)
	coordinator.reinforcement_threshold_reached.connect(
		func(trigger_name: String, _tags: Array[String]) -> void:
			reached_triggers.append(trigger_name)
	)
	expect(
		bool(coordinator.call("apply_directive", {"kind": "set_posture", "value": "airfield_layered_defense", "source_status": "remake_editorial"})),
		"coordinator accepts a labelled posture directive",
		failures,
	)
	expect(
		first_enemy.applied_posture == "airfield_layered_defense"
		and first_enemy.applied_tags == ["airfield_layered_defense", "protect_fuel_and_tower"],
		"posture and cooperation tags are pushed into live enemy behavior",
		failures,
	)
	expect(
		not bool(coordinator.call("observe_mission_event", "item_acquired"))
		and not bool(coordinator.get("reinforcement_trigger_reached")),
		"an unrelated world event leaves the final-level reinforcement threshold armed",
		failures,
	)
	expect(
		bool(coordinator.call("observe_mission_event", "role_eliminated", {"role_id": "m011_air_commander"}))
		and bool(coordinator.get("reinforcement_trigger_reached"))
		and reached_triggers == ["commander_eliminated"],
		"the authored commander-eliminated threshold performs one durable state transition",
		failures,
	)
	expect(
		bool(coordinator.call("apply_directive", {"kind": "release_reinforcement", "value": 3, "source_status": "remake_editorial"}))
		and reinforcement_counts == [3]
		and int(coordinator.get("reinforcement_budget_remaining")) == 2,
		"reinforcement directive spends but cannot bypass the level budget",
		failures,
	)
	var ai_snapshot: Dictionary = coordinator.call("capture_state")
	expect(
		bool(ai_snapshot.get("reinforcement_trigger_reached", false))
		and str(ai_snapshot.get("reinforcement_trigger_source", "")) == "role_eliminated",
		"reinforcement-threshold state is saveable rather than a transient label",
		failures,
	)
	var editorial_enemy = ENEMY_UNIT_SCRIPT.new()
	editorial_enemy.scene_index = 77
	editorial_enemy.position = Vector2.ZERO
	editorial_enemy.weapon_profile = {
		"attack_type": 2,
		"horizontal_range": 200.0,
		"vertical_range": 100.0,
	}
	editorial_enemy.configure_editorial_ai(
		coordinator,
		{"aim_error_multiplier": 1.25, "reaction_time_multiplier": 1.0},
		{"regroup_seconds": 2.0, "tags": ["protect_test"]},
	)
	var early_miss_chance := float(editorial_enemy.editorial_aim_miss_chance(fake_target))
	editorial_enemy.editorial_aim_error_multiplier = 0.89
	var late_miss_chance := float(editorial_enemy.editorial_aim_miss_chance(fake_target))
	expect(
		early_miss_chance > late_miss_chance
		and is_equal_approx(
			ENEMY_UNIT_SCRIPT.deterministic_aim_sample(77, 4),
			ENEMY_UNIT_SCRIPT.deterministic_aim_sample(77, 4)
		),
		"authored aim error changes a deterministic per-shot miss probability",
		failures,
	)
	editorial_enemy.pending_hit_resolved = false
	editorial_enemy.set("_pending_editorial_aim_miss", true)
	editorial_enemy.call("_resolve_pending_hit")
	expect(
		bool(editorial_enemy.pending_hit_resolved),
		"a sampled editorial miss is consumed by the real attack hit resolver",
		failures,
	)
	editorial_enemy.current_target = fake_target
	editorial_enemy.call("_enter_regroup")
	var regroup_start := float(editorial_enemy.regroup_remaining)
	editorial_enemy.call("_update_behavior", regroup_start * 0.5)
	var regroup_mid := float(editorial_enemy.regroup_remaining)
	editorial_enemy.call("_update_behavior", regroup_start)
	expect(
		is_equal_approx(regroup_start, 1.8)
		and regroup_start > regroup_mid
		and editorial_enemy.behavior_state == ENEMY_UNIT_SCRIPT.BehaviorState.CHASE,
		"a denied attacker consumes regroup timing plus protect-tag cadence, then rejoins the chase",
		failures,
	)
	editorial_enemy.free()
	expect(
		AI_COORDINATOR_SCRIPT.deterministic_chance(101, 7, 0.35)
		== AI_COORDINATOR_SCRIPT.deterministic_chance(101, 7, 0.35),
		"flank/suppression sampling is deterministic for replay",
		failures,
	)
	var bridge_runtime: Node = DIRECTION_RUNTIME_SCRIPT.new()
	root.add_child(bridge_runtime)
	var bridge_coordinator: Node = AI_COORDINATOR_SCRIPT.new()
	root.add_child(bridge_coordinator)
	expect(
		bool(bridge_runtime.call("configure_for_mission", "m003"))
		and bool(bridge_coordinator.call(
			"configure",
			bridge_runtime.call("difficulty_profile"),
			bridge_runtime.call("ai_cooperation_profile"),
		)),
		"a counted second-charge reinforcement threshold configures independently",
		failures,
	)
	expect(
		not bool(bridge_coordinator.call("observe_mission_event", "trigger_activated"))
		and not bool(bridge_coordinator.get("reinforcement_trigger_reached")),
		"the first planted charge does not prematurely cross a second-charge threshold",
		failures,
	)
	expect(
		bool(bridge_coordinator.call("observe_mission_event", "trigger_activated"))
		and bool(bridge_coordinator.get("reinforcement_trigger_reached")),
		"the second planted charge performs the configured counted threshold transition",
		failures,
	)

	var invalid_provenance := direction_catalog.duplicate(true) as Dictionary
	(invalid_provenance["provenance"] as Dictionary)["original_dialogue_claimed"] = true
	expect(
		not DIRECTION_DATA_SCRIPT.validate_catalog(invalid_provenance, mission_catalog).is_empty(),
		"validator rejects an unsupported original-dialogue claim",
		failures,
	)
	var invalid_binding := direction_catalog.duplicate(true) as Dictionary
	var invalid_first_plan := (invalid_binding["missions"] as Array)[0] as Dictionary
	var invalid_first_beat := (invalid_first_plan["beats"] as Array)[0] as Dictionary
	(invalid_first_beat["camera"] as Dictionary)["binding"] = "not_a_recovered_scene_binding"
	expect(
		not DIRECTION_DATA_SCRIPT.validate_catalog(invalid_binding, mission_catalog).is_empty(),
		"validator rejects a camera invented outside recovered scene bindings",
		failures,
	)
	var invalid_dialogue := direction_catalog.duplicate(true) as Dictionary
	var invalid_dialogue_plan := (invalid_dialogue["missions"] as Array)[0] as Dictionary
	var invalid_dialogue_beat := (invalid_dialogue_plan["beats"] as Array)[0] as Dictionary
	(invalid_dialogue_beat["dialogue"] as Dictionary)["source_status"] = "recovered_transcript"
	expect(
		not DIRECTION_DATA_SCRIPT.validate_catalog(invalid_dialogue, mission_catalog).is_empty(),
		"validator rejects editorial text relabelled as a recovered transcript",
		failures,
	)

	for enemy: Node2D in fake_enemies:
		root.remove_child(enemy)
		enemy.free()
	for node: Node in [
		runtime,
		timed_runtime,
		restored,
		fake_media,
		queued_runtime,
		queued_media,
		ai_runtime,
		coordinator,
		fake_target,
		bridge_runtime,
		bridge_coordinator,
	]:
		root.remove_child(node)
		node.free()
	if failures.is_empty():
		print(
			"Mission direction tests passed (%d checks; %d beats, %d editorial lines across 12 levels). No original game data was used."
			% [checks, total_beats, total_lines]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func expect(condition: bool, message: String, failures: Array[String]) -> void:
	checks += 1
	if not condition:
		failures.append(message)
