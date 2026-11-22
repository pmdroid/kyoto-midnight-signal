extends Node2D
## Opening vertical slice: fixed-camera 2D room, wordless story, controller-first input.
const Story = preload("res://scripts/story.gd")
const Actor = preload("res://scripts/actor.gd")
const Sound = preload("res://scripts/sound.gd")
const BACKGROUND = preload("res://assets/apartment.png")
const UI_FONT = preload("res://assets/fonts/Interface.ttf")
const TITLE_FONT = preload("res://assets/fonts/Story.ttf")
const SAVE_PATH = "user://opening-v1.json"
const BALL_TARGET = Vector2(895, 575)
const LOST_TARGET = Vector2(612, 505)
const DESK_POINT = Vector2(666, 445)
const LEASH_POINT = Vector2(475, 596)
const DOOR_POINT = Vector2(397, 606)
const MOON_COLOR = Color("a8edff")
var story = Story.new()
var player: Node2D
var dog: Node2D
var sound: Node
var hud: Control
var menu: Control
var menu_buttons: VBoxContainer
var prompt: Label
var controls: Label
var progress: Label
var chapter: Label
var save_label: Label
var menu_title: Label
var menu_subtitle: Label
var menu_eyebrow: Label
var elapsed: float = 0.0
var menu_open: bool = true
var menu_kind: String = "title"
var began: bool = false
var using_pad: bool = false
var pad_was_connected: bool = false
var dog_path: PackedVector2Array = PackedVector2Array()
var dog_target: Vector2 = Vector2.ZERO
var dog_repath: float = 0.0
var walk_target: Vector2 = Vector2.INF
var player_path: PackedVector2Array = PackedVector2Array()
var nav := AStarGrid2D.new()
var free_cells: Array[Vector2i] = []
var ball: Vector2 = Vector2.ZERO
var ball_from: Vector2 = Vector2.ZERO
var ball_flight: float = -1.0
var ball_end: Vector2 = Vector2.ZERO
var cue_time: float = 0.0
var idle_time: float = 0.0
var save_time: float = 0.0
var sparkle_time: float = 0.0
var sequence_note: int = -1
var interaction: String = ""
var focus_target: Vector2 = Vector2.ZERO
var step_time: float = 0.0
var lamp_on: bool = true
var departing: bool = false
var departure_time: float = 0.0
var rain_seed: Array[Vector3] = []
var test_mode: bool = false
var storage_available: bool = true
var checks_failed: bool = false
var qa_web: bool = false
var qa_clock: float = 0.0

func _ready() -> void:
	test_mode = "--smoke-test" in OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		qa_web = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('qa') === '1'"))
	_setup_inputs()
	_build_navigation()
	player = Actor.new()
	player.position = Vector2(726, 520)
	player.scale = Vector2(0.70, 0.70)
	add_child(player)
	dog = Actor.new()
	dog.is_dog = true
	dog.position = Vector2(865, 520)
	dog.scale = Vector2(0.70, 0.70)
	dog.direction = Vector2.LEFT
	add_child(dog)
	sound = Sound.new()
	add_child(sound)
	var stream: AudioStreamWAV = sound.music.stream
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_build_ui()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(38): rain_seed.append(Vector3(rng.randf_range(694, 925), rng.randf_range(0, 1), rng.randf_range(22, 48)))
	Input.joy_connection_changed.connect(_on_pad_connection)
	pad_was_connected = not Input.get_connected_joypads().is_empty()
	using_pad = pad_was_connected
	_show_menu("title")
	if test_mode: call_deferred("_run_smoke_test")

func _setup_inputs() -> void:
	var bindings := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "interact": [KEY_E, KEY_SPACE], "ask_kyoto": [KEY_Q], "pet": [KEY_F], "pause_game": [KEY_ESCAPE], "cancel_item": [KEY_BACKSPACE]}
	for action in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action, 0.22)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	var buttons := {"interact": JOY_BUTTON_A, "ask_kyoto": JOY_BUTTON_X, "pet": JOY_BUTTON_Y, "pause_game": JOY_BUTTON_START, "cancel_item": JOY_BUTTON_B}
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	InputMap.action_add_event("ui_accept", accept)
	for action in buttons:
		var event := InputEventJoypadButton.new()
		event.button_index = buttons[action]
		InputMap.action_add_event(action, event)
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		var event := InputEventJoypadMotion.new()
		event.axis = JOY_AXIS_LEFT_X if action in ["move_left", "move_right"] else JOY_AXIS_LEFT_Y
		event.axis_value = -1.0 if action in ["move_left", "move_up"] else 1.0
		InputMap.action_add_event(action, event)
		var dpad := InputEventJoypadButton.new()
		dpad.button_index = {"move_left": JOY_BUTTON_DPAD_LEFT, "move_right": JOY_BUTTON_DPAD_RIGHT, "move_up": JOY_BUTTON_DPAD_UP, "move_down": JOY_BUTTON_DPAD_DOWN}[action]
		InputMap.action_add_event(action, dpad)

func walkable(p: Vector2) -> bool:
	var floor_ok: bool = Rect2(644, 332, 328, 282).has_point(p) or Rect2(482, 592, 610, 45).has_point(p) or Rect2(350, 586, 140, 69).has_point(p) or Rect2(470, 521, 210, 96).has_point(p) or Rect2(630, 510, 350, 126).has_point(p)
	return floor_ok and p.distance_to(Vector2(566, 591)) > 43.0

func _build_navigation() -> void:
	nav.region = Rect2i(20, 18, 51, 25)
	nav.cell_size = Vector2(12, 12) # Replaced by region below: 12px navigation cells.
	nav.region = Rect2i(27, 25, 66, 31)
	nav.offset = Vector2(6, 6)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for x in range(27, 93):
		for y in range(25, 56):
			var cell := Vector2i(x, y)
			var p := Vector2(cell) * 12 + Vector2(6, 6)
			var solid := not walkable(p)
			nav.set_point_solid(cell, solid)
			if not solid: free_cells.append(cell)

func nearest_cell(p: Vector2) -> Vector2i:
	var best := free_cells[0]
	var distance: float = INF
	for cell in free_cells:
		var d: float = (Vector2(cell) * 12 + Vector2(6, 6)).distance_squared_to(p)
		if d < distance:
			distance = d
			best = cell
	return best

func path_to(from: Vector2, to: Vector2) -> PackedVector2Array:
	return nav.get_point_path(nearest_cell(from), nearest_cell(to))

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.25): using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton: using_pad = false
	if event.is_action_pressed("pause_game"):
		get_viewport().set_input_as_handled()
		if not began: return
		if menu_open and menu_kind == "pause": _close_menu()
		elif not menu_open and not departing: _show_menu("pause")

func _unhandled_input(event: InputEvent) -> void:
	if menu_open or departing: return
	if event.is_action_pressed("interact"):
		_interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ask_kyoto"):
		_ask_kyoto()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pet"):
		_pet()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		player_path = path_to(player.position, get_global_mouse_position())

func _process(dt: float) -> void:
	elapsed += dt
	if qa_web:
		qa_clock += dt
		if qa_clock > 0.15:
			qa_clock = 0
			var state := {"phase": story.phase, "menu": menu_kind if menu_open else "", "position": [player.position.x, player.position.y], "dog": [dog.position.x, dog.position.y], "interaction": interaction, "pad": using_pad, "pets": story.pets}
			JavaScriptBridge.eval("window.__kyoto = " + JSON.stringify(state))
	if not menu_open:
		story.seconds += dt
		idle_time += dt
		cue_time = maxf(0, cue_time - dt)
		sparkle_time = maxf(0, sparkle_time - dt)
		save_time = maxf(0, save_time - dt)
		if departing:
			departure_time += dt
			if departure_time > 2.2:
				departing = false
				_change(Story.Phase.COMPLETE)
				_show_menu("complete")
		else:
			_move_player(dt)
			_update_story(dt)
			_move_dog(dt)
		_update_carried()
	player.tick(dt if not menu_open else dt * 0.3)
	dog.tick(dt if not menu_open else dt * 0.3)
	_update_hud()
	queue_redraw()

func _move_player(dt: float) -> void:
	var axis := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if axis.length() > 0.05: player_path.clear()
	elif not player_path.is_empty():
		if player.position.distance_to(player_path[0]) < 7:
			player_path.remove_at(0)
		if not player_path.is_empty(): axis = player.position.direction_to(player_path[0])
	if story.phase == Story.Phase.SIGNAL: axis = Vector2.ZERO
	var motion: Vector2 = axis * Vector2(148, 110) * dt
	var old: Vector2 = player.position
	if walkable(player.position + Vector2(motion.x, 0)): player.position.x += motion.x
	if walkable(player.position + Vector2(0, motion.y)): player.position.y += motion.y
	player.moving = old.distance_to(player.position) > 0.1
	if player.moving:
		player.direction = axis.normalized()
		idle_time = 0
		step_time += dt
		if step_time > 0.34:
			step_time = 0
			sound.note(110 + int(elapsed * 13) % 30, 0.055, -33)

func _dog_goal() -> Vector2:
	match story.phase:
		Story.Phase.GREETING: return Vector2(854, 523)
		Story.Phase.FETCH_FIRST: return BALL_TARGET
		Story.Phase.RETURN_FIRST: return player.position + Vector2(66, 0)
		Story.Phase.OFFER_SECOND, Story.Phase.HOLD_FIRST, Story.Phase.HOLD_SECOND:
			return player.position + Vector2(78, 12)
		Story.Phase.FETCH_SECOND, Story.Phase.STUCK, Story.Phase.SEARCH: return LOST_TARGET + Vector2(27, 25)
		Story.Phase.OFFER_ORB: return Vector2(688, 543)
		Story.Phase.HOLD_ORB: return Vector2(700, 445)
		Story.Phase.SIGNAL: return Vector2(735, 476)
		Story.Phase.LEASH: return Vector2(490, 602)
		Story.Phase.EXIT: return DOOR_POINT + Vector2(35, 12)
	return player.position + Vector2(78, 0)

func _move_dog(dt: float) -> void:
	dog_repath -= dt
	var goal := _dog_goal()
	if dog_repath < 0:
		dog_repath = 0.45
		dog_target = goal
		dog_path = path_to(dog.position, goal)
		if not dog_path.is_empty() and dog.position.distance_to(dog_path[0]) < 15: dog_path.remove_at(0)
	dog.moving = false
	if not dog_path.is_empty():
		var target: Vector2 = dog_path[0]
		var difference: Vector2 = target - dog.position
		var speed: float = 165.0 if story.phase in [Story.Phase.FETCH_FIRST, Story.Phase.FETCH_SECOND] else 115.0
		if difference.length() < speed * dt + 1:
			dog.position = target
			dog_path.remove_at(0)
		else:
			dog.position += difference.normalized() * speed * dt
			dog.direction = difference.normalized()
			dog.moving = true
	if not dog.moving: dog.direction = dog.position.direction_to(player.position)
	dog.sitting = story.phase in [Story.Phase.GREETING, Story.Phase.SIGNAL, Story.Phase.LEASH, Story.Phase.EXIT] and not dog.moving

func _update_story(dt: float) -> void:
	if ball_flight >= 0:
		ball_flight += dt
		var t := minf(ball_flight / 0.65, 1.0)
		ball = ball_from.lerp(ball_end, t) + Vector2(0, -sin(t * PI) * 85)
		if t >= 1.0:
			ball_flight = -1
			sound.note(195, 0.15, -20)
	match story.phase:
		Story.Phase.FETCH_FIRST:
			if dog.position.distance_to(BALL_TARGET) < 23 and ball_flight < 0: _change(Story.Phase.RETURN_FIRST)
		Story.Phase.RETURN_FIRST:
			if dog.position.distance_to(player.position) < 95: _change(Story.Phase.OFFER_SECOND)
		Story.Phase.FETCH_SECOND:
			if dog.position.distance_to(LOST_TARGET) < 65 and ball_flight < 0: _change(Story.Phase.STUCK)
		Story.Phase.SEARCH:
			if story.seconds > 2.6:
				sparkle_time = 3
				_change(Story.Phase.OFFER_ORB)
				sound.note(659.25, 1.0, -10)
		Story.Phase.SIGNAL:
			var beat := int(story.seconds / 0.9)
			if beat != sequence_note and beat < 6:
				sequence_note = beat
				var notes := [329.63, 493.88, 659.25, 329.63, 493.88, 659.25]
				sound.note(notes[beat], 1.2, -11)
			if story.seconds > 5.6:
				sparkle_time = 2
				_change(Story.Phase.LEASH)
		Story.Phase.STUCK:
			if fmod(story.seconds, 2.2) < dt: sound.note(240, 0.12, -25)

func _update_carried() -> void:
	player.carrying = 0
	dog.carrying = 0
	if story.phase in [Story.Phase.HOLD_FIRST, Story.Phase.HOLD_SECOND]: player.carrying = 1
	if story.phase in [Story.Phase.GREETING, Story.Phase.RETURN_FIRST, Story.Phase.OFFER_SECOND]: dog.carrying = 1
	if story.phase == Story.Phase.OFFER_ORB: dog.carrying = 2
	if story.phase == Story.Phase.HOLD_ORB: player.carrying = 2

func _primary_target() -> Vector2:
	match story.phase:
		Story.Phase.GREETING, Story.Phase.OFFER_SECOND, Story.Phase.OFFER_ORB: return dog.position
		Story.Phase.HOLD_FIRST, Story.Phase.HOLD_SECOND: return BALL_TARGET
		Story.Phase.STUCK, Story.Phase.SEARCH: return LOST_TARGET + Vector2(20, 20)
		Story.Phase.HOLD_ORB, Story.Phase.SIGNAL: return DESK_POINT
		Story.Phase.LEASH: return LEASH_POINT
		Story.Phase.EXIT: return DOOR_POINT
	return dog.position

func _find_interaction() -> String:
	if departing: return ""
	var near_dog: bool = player.position.distance_to(dog.position) < 110
	match story.phase:
		Story.Phase.GREETING, Story.Phase.OFFER_SECOND:
			if near_dog: return "Take ball"
		Story.Phase.HOLD_FIRST, Story.Phase.HOLD_SECOND: return "Throw"
		Story.Phase.STUCK:
			if player.position.distance_to(LOST_TARGET) < 150: return "Ask Kyoto"
		Story.Phase.OFFER_ORB:
			if near_dog: return "Take sphere"
		Story.Phase.HOLD_ORB:
			if player.position.distance_to(DESK_POINT) < 100: return "Investigate"
		Story.Phase.LEASH:
			if player.position.distance_to(LEASH_POINT) < 78: return "Take leash"
		Story.Phase.EXIT:
			if player.position.distance_to(DOOR_POINT) < 65: return "Go outside"
	if story.phase in [Story.Phase.FETCH_FIRST, Story.Phase.RETURN_FIRST, Story.Phase.FETCH_SECOND, Story.Phase.SEARCH, Story.Phase.SIGNAL]: return ""
	if player.position.distance_to(Vector2(817, 352)) < 65: return "Watch the rain"
	if player.position.distance_to(Vector2(953, 359)) < 50: return "Touch the lantern"
	if near_dog: return "Pet Kyoto"
	return ""

func _interact() -> void:
	interaction = _find_interaction()
	idle_time = 0
	match interaction:
		"Take ball":
			_change(Story.Phase.HOLD_FIRST if story.phase == Story.Phase.GREETING else Story.Phase.HOLD_SECOND)
			sound.note(392, 0.2)
		"Throw":
			ball_from = player.position + Vector2(25, -76)
			ball_end = BALL_TARGET if story.phase == Story.Phase.HOLD_FIRST else LOST_TARGET
			ball = ball_from
			ball_flight = 0
			_change(Story.Phase.FETCH_FIRST if story.phase == Story.Phase.HOLD_FIRST else Story.Phase.FETCH_SECOND)
			sound.note(480, 0.16, -22)
		"Ask Kyoto": _begin_search()
		"Take sphere":
			_change(Story.Phase.HOLD_ORB)
			sound.note(493.88, 0.8)
		"Investigate":
			sequence_note = -1
			_change(Story.Phase.SIGNAL)
		"Take leash":
			_change(Story.Phase.EXIT)
			dog.heart_time = 2.5
			sound.note(523.25, 0.35)
		"Go outside":
			departing = true
			departure_time = 0
			player.moving = false
			sound.note(329.63, 1.5, -12)
		"Pet Kyoto": _pet()
		"Watch the rain":
			story.discoveries["rain"] = true
			sparkle_time = 3
			sound.note(880, 1.0, -24)
			_save()
		"Touch the lantern":
			lamp_on = not lamp_on
			story.discoveries["lantern"] = true
			sound.note(220, 0.1, -22)
			_save()

func _ask_kyoto() -> void:
	idle_time = 0
	cue_time = 5
	if story.phase == Story.Phase.STUCK and player.position.distance_to(LOST_TARGET) < 160: _begin_search()
	else: sound.note(440, 0.12, -21)

func _begin_search() -> void:
	_change(Story.Phase.SEARCH)
	sound.note(260, 0.15, -20)

func _pet() -> void:
	if player.position.distance_to(dog.position) < 125:
		dog.heart_time = 2.5
		story.pets += 1
		story.discoveries["friend"] = true
		sound.note(523.25, 0.25, -22)
		_save()
	else: cue_time = 3

func _change(next: int) -> void:
	story.change(next)
	dog_repath = 0
	idle_time = 0
	_save()

func _save() -> void:
	if test_mode: return
	var data: Dictionary = story.snapshot()
	data["position"] = [player.position.x, player.position.y]
	data["muted"] = sound.muted
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		save_time = 1.8
	else: storage_available = false

func _saved_data() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH): return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return {}
	var data = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary else {}

func _begin(restore_save: bool = false) -> void:
	story = Story.new()
	player.position = Vector2(726, 520)
	dog.position = Vector2(854, 523)
	if restore_save:
		var data := _saved_data()
		if story.restore(data):
			var coords = data.get("position", [])
			if coords is Array and coords.size() == 2 and (coords[0] is float or coords[0] is int) and (coords[1] is float or coords[1] is int):
				var p := Vector2(coords[0], coords[1])
				if walkable(p): player.position = p
			sound.set_muted(bool(data.get("muted", false)))
			if story.phase == Story.Phase.COMPLETE: story.change(Story.Phase.EXIT)
			dog.position = Vector2(nearest_cell(_dog_goal())) * 12 + Vector2(6, 6)
	began = true
	departing = false
	ball_flight = -1
	dog_repath = 0
	cue_time = 3
	player_path.clear()
	_close_menu()
	sound.start()
	_save()

func _on_pad_connection(_device: int, connected: bool) -> void:
	if not connected and using_pad and began and not menu_open: _show_menu("pause")
	pad_was_connected = connected

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and began and not menu_open and not test_mode: _show_menu("pause")

func _draw() -> void:
	draw_texture(BACKGROUND, Vector2.ZERO)
	# Rain stays inside the window. Ambient motion continues softly on the title screen.
	for drop in rain_seed:
		var y: float = 195 + fmod(drop.y * 60 + elapsed * drop.z, 55)
		draw_line(Vector2(drop.x, y), Vector2(drop.x - 2, y + 6), Color(0.55, 0.79, 1.0, 0.19), 1.1, true)
	# Contact rings and hints are visual, not written quest descriptions.
	if not menu_open:
		for i in range(5):
			var point := Vector2(1275 + i * 39, 66)
			if i < story.milestone(): draw_circle(point, 5.0, Color("e3b88a"))
			else: draw_arc(point, 5.0, 0, TAU, 20, Color("8e768c"), 1.4, true)
		var target := _primary_target()
		if cue_time > 0 or idle_time > 10:
			_draw_trail(player.position, target)
			var pulse: float = 0.5 + 0.5 * sin(elapsed * 3)
			draw_arc(target, 25 + pulse * 5, 0, TAU, 40, Color(0.94, 0.73, 0.46, 0.35 + pulse * 0.3), 2, true)
		if story.phase in [Story.Phase.FETCH_FIRST, Story.Phase.FETCH_SECOND] and (ball_flight >= 0 or story.phase == Story.Phase.FETCH_FIRST):
			draw_circle(ball, 8, Color("e1ce68"))
			draw_arc(ball, 6, -1.5, 1.5, 12, Color("fff0b4"), 1.3, true)
		if story.phase in [Story.Phase.STUCK, Story.Phase.SEARCH]:
			var p := LOST_TARGET + Vector2(-5, -25)
			for i in range(3):
				var a: float = -2.7 + i * 0.7
				var offset := Vector2(cos(a), sin(a))
				draw_line(p + offset * 17, p + offset * (23 + sin(elapsed * 5) * 3), Color("ecd5a0"), 2, true)
		if story.phase == Story.Phase.SEARCH:
			for i in range(6):
				var p := LOST_TARGET + Vector2(sin(elapsed * 2 + i) * 20, -story.seconds * 9 - i * 4)
				draw_circle(p, 1.7, MOON_COLOR)
	# The desktop screen awakens only after the sphere reaches it.
	if story.phase >= Story.Phase.SIGNAL:
		var intensity: float = 1.0
		if story.phase == Story.Phase.SIGNAL: intensity = clampf(story.seconds / 2.5, 0.0, 1.0)
		_draw_monitor(intensity)
	if not lamp_on:
		draw_circle(Vector2(1000, 320), 27, Color(0.08, 0.04, 0.13, 0.3))
	if sparkle_time > 0:
		for i in range(12):
			var p := Vector2(740 + sin(i * 12.5 + elapsed) * 150, 430 + cos(i * 7.3 + elapsed * 0.6) * 100)
			draw_circle(p, 1.4, Color(0.6, 0.9, 1.0, sparkle_time / 3.0))
	if story.phase >= Story.Phase.EXIT:
		# A little cyan rim at the door foreshadows the world outside.
		draw_line(Vector2(370, 572), Vector2(423, 572), Color(0.42, 0.82, 1.0, 0.6), 3)
	if departing:
		var alpha := clampf(departure_time, 0.0, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(370, 571), Vector2(423, 571), Vector2(490, 644), Vector2(350, 644)]), Color(0.55, 0.8, 1.0, alpha * 0.3))

func _draw_trail(from: Vector2, to: Vector2) -> void:
	var route := path_to(from, to)
	for i in range(2, route.size(), 3):
		var alpha: float = 0.25 + 0.2 * sin(elapsed * 3 - i * 0.4)
		var p := route[i]
		draw_circle(p, 2.5, Color(1, 0.8, 0.53, alpha))
		draw_circle(p + Vector2(-3, -4), 1.3, Color(1, 0.8, 0.53, alpha))
		draw_circle(p + Vector2(2, -5), 1.3, Color(1, 0.8, 0.53, alpha))

func _draw_monitor(intensity: float) -> void:
	var screen := PackedVector2Array([Vector2(506, 352), Vector2(549, 321), Vector2(559, 357), Vector2(518, 387)])
	draw_colored_polygon(screen, Color(0.08, 0.18, 0.30, 0.8 * intensity))
	var p := Vector2(533, 353)
	for i in range(4): draw_circle(p, 21 + i * 3, Color(0.25, 0.7, 1.0, 0.025 * intensity))
	draw_circle(p, 13, Color(0.6, 0.9, 1.0, intensity))
	draw_circle(p + Vector2(6, -4), 12, Color(0.08, 0.18, 0.30, intensity))
	if story.phase == Story.Phase.SIGNAL:
		var radius: float = fmod(story.seconds * 32, 65)
		draw_arc(p, radius, 0, TAU, 40, Color(0.4, 0.8, 1.0, (1.0 - radius / 65) * 0.5), 1.5, true)

func _label(text: String, size_px: int, position_px: Vector2, bounds: Vector2, parent: Node, serif: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_px
	label.size = bounds
	label.add_theme_font_override("font", TITLE_FONT if serif else UI_FONT)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", Color("f5e6cf"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud)
	chapter = _label("KYOTO  /  01", 24, Vector2(64, 40), Vector2(500, 40), hud, true)
	var sub := _label("ONE LAST WALK", 14, Vector2(66, 82), Vector2(500, 30), hud)
	sub.modulate = Color(0.8, 0.74, 0.8)
	progress = _label("", 24, Vector2(1220, 48), Vector2(250, 40), hud)
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prompt = _label("", 24, Vector2(400, 764), Vector2(736, 48), hud)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls = _label("", 19, Vector2(160, 915), Vector2(1216, 50), hud)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.modulate = Color("b7a6bc")
	save_label = _label("", 15, Vector2(1130, 969), Vector2(340, 30), hud)
	save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	save_label.modulate = Color("b7a6bc")
	var note := _label("OPENING PROTOTYPE", 13, Vector2(66, 971), Vector2(350, 30), hud)
	note.modulate = Color("78677f")
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(menu)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.size = Vector2(1536, 1024)
	shade.color = Color(0.035, 0.02, 0.065, 0.12)
	menu.add_child(shade)
	menu_eyebrow = _label("", 16, Vector2(100, 29), Vector2(1336, 30), menu)
	menu_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_eyebrow.modulate = Color("d1a18d")
	menu_title = _label("", 49, Vector2(80, 65), Vector2(1376, 80), menu, true)
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_subtitle = _label("", 18, Vector2(200, 144), Vector2(1136, 45), menu)
	menu_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_subtitle.modulate = Color("c1afc8")
	menu_buttons = VBoxContainer.new()
	menu_buttons.position = Vector2(548, 747)
	menu_buttons.size = Vector2(440, 240)
	menu_buttons.add_theme_constant_override("separation", 12)
	menu.add_child(menu_buttons)

func _button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(440, 56)
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", Color("f6e8cf"))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("463246") if primary else Color("211627")
	normal.border_color = Color("8c646d")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(9)
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	button.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color("574058")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = Color("efc991")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(9)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(callback)
	menu_buttons.add_child(button)
	return button

func _show_menu(kind: String) -> void:
	menu_kind = kind
	menu_open = true
	menu.show()
	hud.hide()
	player.moving = false
	dog.moving = false
	player_path.clear()
	for child in menu_buttons.get_children():
		menu_buttons.remove_child(child)
		child.queue_free()
	var first: Button
	menu_title.position.y = 65
	menu_subtitle.position.y = 144
	menu_eyebrow.position.y = 29
	menu_buttons.position.y = 747
	menu.get_node("Shade").color.a = 0.12
	match kind:
		"title":
			menu_eyebrow.text = "NEON AFTER HOURS"
			menu_title.text = "Kyoto & the midnight signal"
			menu_subtitle.text = "01  /  ONE LAST WALK"
			var saved := _saved_data()
			if not saved.is_empty():
				first = _button("Continue", func(): _begin(true), true)
				_button("New game", func(): _show_menu("restart"))
			else: first = _button("Begin", func(): _begin(false), true)
			_button("Controls", func(): _show_menu("controls"))
		"pause":
			menu.get_node("Shade").color.a = 0.77
			menu_eyebrow.position.y = 231
			menu_title.position.y = 277
			menu_subtitle.position.y = 350
			menu_buttons.position.y = 426
			menu_eyebrow.text = "TAKE YOUR TIME"
			menu_title.text = "A little pause"
			menu_subtitle.text = "Your progress is saved automatically."
			first = _button("Resume", _close_menu, true)
			_button("Sound: " + ("off" if sound.muted else "on"), _toggle_sound)
			_button("Controls", func(): _show_menu("controls"))
			_button("Restart opening", func(): _show_menu("restart"))
		"restart":
			menu.get_node("Shade").color.a = 0.80
			menu_title.position.y = 280
			menu_subtitle.position.y = 370
			menu_buttons.position.y = 470
			menu_eyebrow.text = ""
			menu_title.text = "Start a new walk?"
			menu_subtitle.text = "This replaces your saved opening."
			first = _button("Keep my progress", func(): _show_menu("pause" if began else "title"), true)
			_button("Start again", func(): _begin(false))
		"controls":
			menu.get_node("Shade").color.a = 0.85
			menu_eyebrow.position.y = 190
			menu_title.position.y = 230
			menu_subtitle.position.y = 328
			menu_subtitle.size.y = 270
			menu_buttons.position.y = 655
			menu_eyebrow.text = "PLAY AT YOUR OWN PACE"
			menu_title.text = "You and Kyoto"
			menu_subtitle.text = "MOVE     Left stick / D-pad  ·  WASD / arrows\nINTERACT     A  ·  E / Space\nASK KYOTO     X  ·  Q\nPET KYOTO     Y  ·  F\nPAUSE     Menu  ·  Esc\n\nYou can also click the floor to walk."
			first = _button("Back", func(): _show_menu("pause" if began else "title"), true)
		"complete":
			menu.get_node("Shade").color.a = 0.48
			menu_eyebrow.text = "THE FIRST SIGNAL"
			menu_title.text = "One last walk…"
			menu_subtitle.text = "Opening complete · The neighborhood is next."
			first = _button("Explore the apartment", _explore_again, true)
			_button("Play again", func(): _show_menu("restart"))
	if kind != "controls": menu_subtitle.size.y = 45
	first.grab_focus()

func _toggle_sound() -> void:
	sound.set_muted(not sound.muted)
	_save()
	_show_menu("pause")
	menu_buttons.get_child(1).grab_focus()

func _explore_again() -> void:
	story.change(Story.Phase.EXIT)
	player.position = Vector2(700, 560)
	dog.position = Vector2(790, 560)
	dog_repath = 0
	_close_menu()

func _close_menu() -> void:
	menu_open = false
	menu.hide()
	hud.show()

func _update_hud() -> void:
	interaction = _find_interaction()
	var key := "A" if using_pad else "E"
	if interaction == "Ask Kyoto": key = "X" if using_pad else "Q"
	prompt.text = "[ " + key + " ]  " + interaction if interaction != "" else ""
	if story.phase == Story.Phase.SIGNAL: prompt.text = ""
	if story.phase in [Story.Phase.FETCH_FIRST, Story.Phase.RETURN_FIRST, Story.Phase.FETCH_SECOND, Story.Phase.SEARCH]: prompt.text = ""
	controls.text = "Left stick  Move     A  Interact     X  Ask Kyoto     Y  Pet     Menu  Pause" if using_pad else "WASD  Move     E  Interact     Q  Ask Kyoto     F  Pet     Esc  Pause"
	var dots: String = ""
	for i in range(5): dots += ("●" if i < story.milestone() else "○") + "   "
	progress.text = ""
	save_label.text = "Saved" if save_time > 0 else ""
	if not storage_available: save_label.text = "Saving unavailable in this browser session"

func _run_smoke_test() -> void:
	# Tests the actual input handlers and progression without rendering.
	_begin(false)
	_check(story.phase == Story.Phase.GREETING)
	player.position = dog.position + Vector2(-65, 0)
	_interact()
	_check(story.phase == Story.Phase.HOLD_FIRST)
	_interact()
	_check(story.phase == Story.Phase.FETCH_FIRST)
	ball_flight = -1
	dog.position = BALL_TARGET
	_update_story(0.1)
	_check(story.phase == Story.Phase.RETURN_FIRST)
	dog.position = player.position + Vector2(65, 0)
	_update_story(0.1)
	_check(story.phase == Story.Phase.OFFER_SECOND)
	_interact()
	_interact()
	_check(story.phase == Story.Phase.FETCH_SECOND)
	ball_flight = -1
	dog.position = LOST_TARGET + Vector2(30, 25)
	_update_story(0.1)
	_check(story.phase == Story.Phase.STUCK)
	player.position = Vector2(670, 550)
	_ask_kyoto()
	_check(story.phase == Story.Phase.SEARCH)
	story.seconds = 3
	_update_story(0.1)
	_check(story.phase == Story.Phase.OFFER_ORB)
	dog.position = Vector2(688, 543)
	_interact()
	_check(story.phase == Story.Phase.HOLD_ORB)
	player.position = DESK_POINT
	_interact()
	_check(story.phase == Story.Phase.SIGNAL)
	story.seconds = 6
	_update_story(0.1)
	_check(story.phase == Story.Phase.LEASH)
	player.position = LEASH_POINT
	_interact()
	_check(story.phase == Story.Phase.EXIT)
	player.position = DOOR_POINT
	_interact()
	_check(departing)
	# All authored goals are reachable through the same navigation used by Kyoto.
	for goal in [BALL_TARGET, LOST_TARGET, DESK_POINT, LEASH_POINT, DOOR_POINT, Vector2(817, 352)]:
		_check(path_to(Vector2(720, 530), goal).size() > 0)
	for phase in range(Story.Phase.COMPLETE + 1):
		story.change(phase)
		var restored = Story.new()
		_check(restored.restore(story.snapshot()))
		_check(restored.phase not in [Story.Phase.FETCH_FIRST, Story.Phase.RETURN_FIRST, Story.Phase.FETCH_SECOND, Story.Phase.SEARCH, Story.Phase.SIGNAL])
	_check(not Story.new().restore({"version": 1, "phase": 999}))
	_check(not Story.new().restore({"version": 1, "phase": "bad"}))
	if checks_failed:
		get_tree().quit(1)
		return
	print("PASS: opening progression, interaction handlers, navigation, save checkpoints, invalid saves")
	var tree := get_tree()
	queue_free()
	tree.create_timer(0.1).timeout.connect(tree.quit)

func _check(condition: bool) -> void:
	if not condition:
		checks_failed = true
		push_error("Opening smoke check failed at phase " + str(story.phase))
