extends SceneTree

const MEDIA_ROUTES: Script = preload(
	"res://scripts/generated/legacy_media_route_catalog.gd"
)
const STARTUP_QUEUE: Script = preload(
	"res://scripts/original_startup_media_queue.gd"
)

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_test_static_original_media_routes()
	_test_startup_queue_order_and_resolution()
	_test_missing_conversion_degradation()
	if failures.is_empty():
		print(
			"Legacy media-order tests passed (%d checks). No movie playback or mission playthrough was used."
			% checks
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_static_original_media_routes() -> void:
	_expect(
		MEDIA_ROUTES.MOVIE_PLAYER_BLOCKS
		and MEDIA_ROUTES.EXECUTABLE_SVT_STRING_COUNT == 2
		and MEDIA_ROUTES.DIRECT_MOVIE_CALL_COUNT == 2
		and MEDIA_ROUTES.INTER_LEVEL_MOVIE_COUNT == 0,
		"the executable has exactly two blocking startup movies and no inter-level movie",
	)
	var startup: Array[Dictionary] = MEDIA_ROUTES.startup_sequence()
	_expect(
		startup.size() == 2
		and str(startup[0].get("id", "")) == "logo"
		and str(startup[0].get("source_filename", "")) == "GameKingLogo.SVT"
		and int(startup[0].get("call_rva", 0)) == 0x7635
		and int(startup[0].get("player_argument_2", -1)) == 0
		and str(startup[1].get("id", "")) == "historical_intro"
		and str(startup[1].get("source_filename", "")) == "1937Intro.SVT"
		and int(startup[1].get("call_rva", 0)) == 0x7644
		and int(startup[1].get("player_argument_2", -1)) == 100,
		"startup order and raw player arguments match sub_407300",
	)
	_expect(
		MEDIA_ROUTES.LEVEL_BRIEFINGS.size() == 12
		and str(MEDIA_ROUTES.LEVEL_BRIEFINGS[0].get("level_id", "")) == "m000"
		and int(MEDIA_ROUTES.LEVEL_BRIEFINGS[0].get("gfl_index", -1)) == 1048
		and str(MEDIA_ROUTES.LEVEL_BRIEFINGS[11].get("level_id", "")) == "m011"
		and int(MEDIA_ROUTES.LEVEL_BRIEFINGS[11].get("gfl_index", -1)) == 1059,
		"all twelve original briefing routes are contiguous",
	)
	for index: int in range(12):
		var briefing: Dictionary = MEDIA_ROUTES.LEVEL_BRIEFINGS[index]
		_expect(
			int(briefing.get("selector_level", 0)) == index + 1
			and str(briefing.get("level_id", "")) == "m%03d" % index,
			"briefing selector %d maps to its formal mission" % (index + 1),
		)
	_expect(
		MEDIA_ROUTES.ENDING_SELECTOR_LEVEL == 13
		and MEDIA_ROUTES.ENDING_DISMISSAL_NEXT_SELECTOR_LEVEL == 1
		and MEDIA_ROUTES.ENDING_IMAGES.size() == 3
		and int(MEDIA_ROUTES.ENDING_IMAGES[0].get("target_width", 0)) == 640
		and int(MEDIA_ROUTES.ENDING_IMAGES[1].get("target_width", 0)) == 800
		and int(MEDIA_ROUTES.ENDING_IMAGES[2].get("target_width", 0)) == 1024,
		"selector 13 uses the three original resolution-dependent ending images",
	)
	_expect(
		MEDIA_ROUTES.PRESENTATION_STRING_COUNT == 27
		and MEDIA_ROUTES.IN_MISSION_DIALOGUE_SEQUENCE_COUNT == 0
		and MEDIA_ROUTES.SCRIPTED_CAMERA_SEQUENCE_COUNT == 0
		and MEDIA_ROUTES.PER_LEVEL_TUTORIAL_SEQUENCE_COUNT == 0
		and not MEDIA_ROUTES.MISSION_FLOW_REACHES_MOVIE_OR_CAMERA,
		"the closed original presentation audit contains no in-mission director sequence",
	)
	_expect(
		str(MEDIA_ROUTES.GLOBAL_HELP.get("resource_name", "")) == "Help.psd"
		and int(MEDIA_ROUTES.GLOBAL_HELP.get("resource_string_rva", 0)) == 0xCF704
		and str(MEDIA_ROUTES.GLOBAL_HELP.get("presenter_symbol", ""))
			== "HelpPresenter"
		and str(MEDIA_ROUTES.GLOBAL_HELP.get("scope", "")) == "global_f1_help",
		"F1 help remains a global source-backed presentation route",
	)
	_expect(
		MEDIA_ROUTES.CAMERA_DIRECT_CALL_COUNT == 2
		and MEDIA_ROUTES.MISSION_SCRIPT_CAMERA_WRITER_COUNT == 0
		and MEDIA_ROUTES.CAMERA_DIRECT_CALLERS.size() == 2
		and int(MEDIA_ROUTES.CAMERA_DIRECT_CALLERS[0].get("call_rva", 0))
			== 0x4CC23
		and str(MEDIA_ROUTES.CAMERA_DIRECT_CALLERS[0].get("role", ""))
			== "world_input_recenter"
		and int(MEDIA_ROUTES.CAMERA_DIRECT_CALLERS[1].get("call_rva", 0))
			== 0x4CD8B
		and str(MEDIA_ROUTES.CAMERA_DIRECT_CALLERS[1].get("role", ""))
			== "explicit_actor_focus",
		"the only direct camera-set calls are world input and explicit actor focus",
	)
	_expect(
		MEDIA_ROUTES.CAMERA_WRITER_SYMBOLS == [
			"InitializeViewport",
			"SetCameraOrigin",
			"ScrollLeft",
			"ScrollRight",
			"ScrollUp",
			"ScrollDown",
			"ResizeViewportWorld",
			"LoadGameFile",
		],
		"camera writers close over initialization, input, resize and save loading only",
	)


func _test_startup_queue_order_and_resolution() -> void:
	var queue: RefCounted = STARTUP_QUEUE.new()
	queue.call("begin", MEDIA_ROUTES.startup_sequence())
	_expect(
		bool(queue.call("is_active"))
		and int(queue.call("remaining_count")) == 2,
		"startup queue begins with two entries",
	)
	var first := str(queue.call("next_movie_id"))
	_expect(
		first == "logo"
		and str(queue.call("awaiting_movie_id")) == "logo"
		and str(queue.call("next_movie_id")).is_empty(),
		"a pending logo cannot be bypassed or duplicated",
	)
	_expect(
		not bool(queue.call("resolve", "historical_intro"))
		and bool(queue.call("resolve", "logo")),
		"only the currently pending movie may advance the queue",
	)
	var second := str(queue.call("next_movie_id"))
	_expect(
		second == "historical_intro"
		and bool(queue.call("resolve", second))
		and not bool(queue.call("is_active"))
		and int(queue.call("remaining_count")) == 0,
		"historical intro follows the logo and exhausts the queue",
	)


func _test_missing_conversion_degradation() -> void:
	_expect(
		_simulate_available_movies({"historical_intro": true})
		== {
			"attempted": ["logo", "historical_intro"],
			"played": ["historical_intro"],
		},
		"a missing logo skips directly to the available historical intro",
	)
	_expect(
		_simulate_available_movies({})
		== {
			"attempted": ["logo", "historical_intro"],
			"played": [],
		},
		"two missing conversions finish immediately without a modal deadlock",
	)


func _simulate_available_movies(available: Dictionary) -> Dictionary:
	var queue: RefCounted = STARTUP_QUEUE.new()
	queue.call("begin", MEDIA_ROUTES.startup_sequence())
	var attempted: Array[String] = []
	var played: Array[String] = []
	while bool(queue.call("is_active")):
		var movie_id := str(queue.call("next_movie_id"))
		if movie_id.is_empty():
			break
		attempted.append(movie_id)
		if bool(available.get(movie_id, false)):
			played.append(movie_id)
		queue.call("resolve", movie_id)
	return {"attempted": attempted, "played": played}


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
