extends "res://scripts/apartment.gd"
## Connected, backtrackable exploration built on the opening's input/UI/audio systems.
const Rooms = preload("res://scripts/room_data.gd")
const WORLD_SAVE = "user://exploration-v2.json"
var room: String = "apartment"
var flags: Dictionary = {}
var found: Dictionary = {}
var revealed: Dictionary = {}
var visited: Dictionary = {"apartment": true}
var has_cell: bool = false
var camera: Camera2D
var camera_zoom: float = 2.65
var transition: ColorRect
var transitioning: bool = false
var inventory_label: Label
var secrets_label: Label
var active_id: String = ""
var found_fx: float = 0.0
var found_at: Vector2
var inspect_fx: float = 0.0
var local_cue: Vector2 = Vector2.INF
var hint_icon: String = ""
var migrated: bool = false

func _ready() -> void:
	super._ready()
	player.scale = Vector2(0.42, 0.42)
	dog.scale = Vector2(0.38, 0.38)
	player.position = Rooms.APARTMENT_START
	dog.position = player.position + Vector2(70, 10)
	camera = Camera2D.new()
	camera.zoom = Vector2(camera_zoom, camera_zoom)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7
	camera.position = player.position + Vector2(0, -55)
	add_child(camera)
	camera.make_current()
	_camera_follow()
	camera.reset_smoothing()
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	transition = ColorRect.new()
	transition.color = Color(0.035, 0.02, 0.06, 0)
	transition.size = Vector2(1536, 1024)
	transition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(transition)
	var panel := Panel.new()
	panel.position = Vector2(310, 892)
	panel.size = Vector2(916, 90)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.025, 0.065, 0.82)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	hud.add_child(panel)
	hud.move_child(panel, 0)
	prompt.position.y = 902
	controls.position.y = 947
	controls.add_theme_font_size_override("font_size", 17)
	inventory_label = _label("", 21, Vector2(1110, 37), Vector2(360, 35), hud)
	inventory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	secrets_label = _label("", 17, Vector2(1110, 76), Vector2(360, 30), hud)
	secrets_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	secrets_label.modulate = Color("d5bbd8")
	progress.hide()
	for box in [Rect2(48,24,530,92), Rect2(1065,24,425,92)]:
		var backing := Panel.new()
		backing.position = box.position
		backing.size = box.size
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.04,0.025,0.065,0.65)
		fill.set_corner_radius_all(9)
		backing.add_theme_stylebox_override("panel",fill)
		hud.add_child(backing)
		hud.move_child(backing,0)
	# Optional zoom adjustment retains a local view; it never becomes a whole-map camera.
	for action in ["zoom_in", "zoom_out"]: InputMap.add_action(action)
	for pair in [["zoom_in", KEY_EQUAL, JOY_BUTTON_RIGHT_SHOULDER], ["zoom_out", KEY_MINUS, JOY_BUTTON_LEFT_SHOULDER]]:
		var k := InputEventKey.new()
		k.physical_keycode = pair[1]
		InputMap.action_add_event(pair[0], k)
		var b := InputEventJoypadButton.new()
		b.button_index = pair[2]
		InputMap.action_add_event(pair[0], b)
		
func walkable(p: Vector2) -> bool:
	return Rooms.walkable(room, p)

func _build_navigation() -> void:
	free_cells.clear()
	nav.region = Rect2i(0, 0, 128, 86)
	nav.cell_size = Vector2(12, 12)
	nav.offset = Vector2(6, 6)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for x in range(128):
		for y in range(86):
			var c := Vector2i(x, y)
			var valid := walkable(Vector2(c) * 12 + Vector2(6, 6))
			nav.set_point_solid(c, not valid)
			if valid: free_cells.append(c)

func _process(dt: float) -> void:
	super._process(dt)
	if not menu_open:
		found_fx = maxf(0, found_fx - dt)
		inspect_fx = maxf(0, inspect_fx - dt)
		if Input.is_action_just_pressed("zoom_in"):
			camera_zoom = minf(3.0, camera_zoom + 0.15)
			_save()
		if Input.is_action_just_pressed("zoom_out"):
			camera_zoom = maxf(2.15, camera_zoom - 0.15)
			_save()
	if is_instance_valid(camera): _camera_follow()
	if qa_web and qa_clock == 0 and is_instance_valid(camera):
		var p: Vector2 = get_viewport().get_canvas_transform() * player.position
		var state := {"phase": story.phase, "room": room, "menu": menu_kind if menu_open else "", "position": [player.position.x, player.position.y], "screen": [p.x,p.y], "camera": [camera.position.x,camera.position.y], "zoom": camera_zoom, "interaction": interaction, "active": active_id, "pad": using_pad, "pets": story.pets, "found": found, "flags":flags,"cell":has_cell,"revealed":revealed,"visited":visited}
		JavaScriptBridge.eval("window.__kyoto = " + JSON.stringify(state))

func _camera_follow() -> void:
	camera.zoom = camera.zoom.lerp(Vector2(camera_zoom, camera_zoom), 0.12)
	var half: Vector2 = Vector2(1536, 1024) / camera_zoom / 2
	var target: Vector2 = player.position + Vector2(0, -55)
	camera.position = Vector2(clampf(target.x, half.x + 24, 1536 - half.x - 24), clampf(target.y, half.y + 24, 1024 - half.y - 24))

func _unhandled_input(event: InputEvent) -> void:
	if transitioning: return
	super._unhandled_input(event)

func _move_player(dt: float) -> void:
	if transitioning:
		player.moving = false
		return
	var axis := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if axis.length() > 0.05: player_path.clear()
	elif not player_path.is_empty():
		if player.position.distance_to(player_path[0]) < 4: player_path.remove_at(0)
		if not player_path.is_empty(): axis = player.position.direction_to(player_path[0])
	if story.phase == Story.Phase.SIGNAL: axis = Vector2.ZERO
	var motion: Vector2 = axis * Vector2(102, 82) * dt
	var old: Vector2 = player.position
	if walkable(player.position + Vector2(motion.x, 0)): player.position.x += motion.x
	if walkable(player.position + Vector2(0, motion.y)): player.position.y += motion.y
	player.moving = old.distance_to(player.position) > 0.02
	if player.moving:
		player.direction = axis.normalized()
		idle_time = 0
		step_time += dt
		if step_time > 0.34:
			step_time = 0
			sound.note(105 + int(elapsed * 9) % 32, 0.055, -33)

func _dog_goal() -> Vector2:
	if room == "apartment" and story.phase < Story.Phase.EXIT:
		match story.phase:
			Story.Phase.GREETING: return Rooms.APARTMENT_START + Vector2(70, 10)
			Story.Phase.FETCH_FIRST: return Rooms.FIRST_FETCH
			Story.Phase.RETURN_FIRST, Story.Phase.OFFER_SECOND, Story.Phase.HOLD_FIRST, Story.Phase.HOLD_SECOND: return player.position + Vector2(38, 9)
			Story.Phase.FETCH_SECOND, Story.Phase.STUCK, Story.Phase.SEARCH: return Rooms.LOST_BALL + Vector2(18, 19)
			Story.Phase.OFFER_ORB: return player.position + Vector2(35, 0)
			Story.Phase.HOLD_ORB, Story.Phase.SIGNAL: return Rooms.MONITOR + Vector2(40, 15)
			Story.Phase.LEASH: return Rooms.LEASH + Vector2(-35, 16)
	if cue_time > 0 and local_cue != Vector2.INF:
		return local_cue
	# Kyoto reacts to nearby hidden things without pointing through the whole level.
	for obj in Rooms.objects(room):
		if obj.hidden and not found.has(obj.id) and player.position.distance_to(obj.p) < 105:
			return obj.p + Vector2(17, 6)
	return player.position + Vector2(-37 if player.direction.x > 0 else 37, 16)

func _move_dog(dt: float) -> void:
	if transitioning:
		dog.moving = false
		return
	dog_repath -= dt
	var goal := _dog_goal()
	if dog_repath < 0:
		dog_repath = 0.4
		dog_target = goal
		dog_path = path_to(dog.position, goal)
		if not dog_path.is_empty() and dog.position.distance_to(dog_path[0]) < 15: dog_path.remove_at(0)
	dog.moving = false
	if not dog_path.is_empty():
		var delta_p: Vector2 = dog_path[0] - dog.position
		var speed := 150.0 if story.phase in [Story.Phase.FETCH_FIRST, Story.Phase.FETCH_SECOND] else 112.0
		if delta_p.length() < speed * dt + 1:
			dog.position = dog_path[0]
			dog_path.remove_at(0)
		else:
			dog.position += delta_p.normalized() * speed * dt
			dog.direction = delta_p.normalized()
			dog.moving = true
	if not dog.moving: dog.direction = dog.position.direction_to(player.position)
	dog.sitting = not dog.moving and story.phase in [Story.Phase.GREETING, Story.Phase.SIGNAL]

func _update_story(dt: float) -> void:
	if transitioning: return
	if ball_flight >= 0:
		ball_flight += dt
		var t := minf(ball_flight / 1.0, 1.0)
		ball = ball_from.lerp(ball_end, t) + Vector2(0, -sin(t * PI) * 64)
		if t >= 1:
			ball_flight = -1
			sound.note(195, 0.15, -20)
	match story.phase:
		Story.Phase.FETCH_FIRST:
			if dog.position.distance_to(Rooms.FIRST_FETCH) < 20 and ball_flight < 0: _change(Story.Phase.RETURN_FIRST)
		Story.Phase.RETURN_FIRST:
			if dog.position.distance_to(player.position) < 58: _change(Story.Phase.OFFER_SECOND)
		Story.Phase.FETCH_SECOND:
			if dog.position.distance_to(Rooms.LOST_BALL) < 48 and ball_flight < 0: _change(Story.Phase.STUCK)
		Story.Phase.SEARCH:
			if story.seconds > 2.6:
				_change(Story.Phase.OFFER_ORB)
				sound.note(659.25, 1.0, -12)
		Story.Phase.SIGNAL:
			var beat := int(story.seconds / 0.9)
			if beat != sequence_note and beat < 6:
				sequence_note = beat
				sound.note([329.63, 493.88, 659.25, 329.63, 493.88, 659.25][beat], 1.2, -11)
			if story.seconds > 5.6: _change(Story.Phase.LEASH)

func _primary_target() -> Vector2:
	if flags.get("greenhouse",false):
		var closest := Vector2.INF
		var distance := INF
		for obj in Rooms.objects(room):
			if not found.has(obj.id) and player.position.distance_to(obj.p) < distance:
				distance = player.position.distance_to(obj.p)
				closest = obj.p
		if closest != Vector2.INF: return closest
	if room == "apartment" and story.phase < Story.Phase.EXIT:
		match story.phase:
			Story.Phase.GREETING, Story.Phase.OFFER_SECOND, Story.Phase.OFFER_ORB: return dog.position
			Story.Phase.HOLD_FIRST, Story.Phase.HOLD_SECOND: return player.position + Vector2(40, 0)
			Story.Phase.FETCH_FIRST: return Rooms.FIRST_FETCH
			Story.Phase.RETURN_FIRST: return dog.position
			Story.Phase.FETCH_SECOND, Story.Phase.STUCK, Story.Phase.SEARCH: return Rooms.LOST_BALL + Vector2(15, 25)
			Story.Phase.HOLD_ORB, Story.Phase.SIGNAL: return Rooms.MONITOR
			Story.Phase.LEASH: return Rooms.LEASH
	match room:
		"apartment":
			if visited.has("hallway") and not flags.get("powered", false) and not has_cell: return Rooms.WORKBENCH
			if visited.has("courtyard") and not found.has("moon_home"): return Vector2(1265,843)
			return Rooms.HOME_DOOR
		"hallway":
			if not flags.get("powered", false): return Rooms.CART if has_cell else Rooms.HALL_HOME
			if visited.has("courtyard") and not found.has("moon_hall"): return Vector2(1435,854)
			return Rooms.HALL_EXIT
		"courtyard":
			if not found.has("moon_garden"): return Vector2(459,366)
			if moon_count() < 3: return Rooms.GARDEN_HOME
			return Rooms.GREENHOUSE
	return dog.position

func _near(p: Vector2, distance: float = 44.0) -> bool:
	return player.position.distance_to(p) < distance

func _find_interaction() -> String:
	active_id = ""
	if transitioning: return ""
	if room == "apartment" and story.phase < Story.Phase.EXIT:
		match story.phase:
			Story.Phase.GREETING, Story.Phase.OFFER_SECOND:
				if _near(dog.position, 66): return "Take ball"
			Story.Phase.HOLD_FIRST, Story.Phase.HOLD_SECOND: return "Throw"
			Story.Phase.STUCK:
				if _near(Rooms.LOST_BALL, 100): return "Ask Kyoto"
			Story.Phase.OFFER_ORB:
				if _near(dog.position, 66): return "Take sphere"
			Story.Phase.HOLD_ORB:
				if _near(Rooms.MONITOR, 55): return "Investigate"
			Story.Phase.LEASH:
				if _near(Rooms.LEASH, 48): return "Take leash"
	if story.phase in [Story.Phase.SIGNAL, Story.Phase.SEARCH]: return ""
	if room == "apartment" and story.phase >= Story.Phase.EXIT and _near(Rooms.HOME_DOOR): return "Enter the hall"
	if room == "hallway":
		if _near(Rooms.HALL_HOME): return "Go home"
		if _near(Rooms.HALL_EXIT): return "Enter the garden" if flags.get("powered",false) else "Check the locked door"
		if _near(Rooms.CART): return ("Fit the power cell" if has_cell else "Inspect the socket") if not flags.get("powered",false) else "Wake the little cart"
	if room == "courtyard":
		if _near(Rooms.GARDEN_HOME): return "Return to the hall"
		if _near(Rooms.GREENHOUSE):
			if flags.get("greenhouse",false): return "Look below"
			return "Place the moon pieces" if moon_count() == 3 else "Inspect the seal"
	var best: Dictionary = {}
	var distance := 58.0
	for obj in Rooms.objects(room):
		if found.has(obj.id): continue
		var d: float = player.position.distance_to(obj.p)
		if d < distance:
			best = obj
			distance = d
	if not best.is_empty():
		active_id = best.id
		if best.hidden and not revealed.has(best.id): return "Ask Kyoto"
		return best.verb
	if _near(dog.position, 60): return "Pet Kyoto"
	return ""

func _interact() -> void:
	interaction = _find_interaction()
	idle_time = 0
	match interaction:
		"Take ball":
			_change(Story.Phase.HOLD_FIRST if story.phase == Story.Phase.GREETING else Story.Phase.HOLD_SECOND)
			sound.note(392, 0.2)
		"Throw":
			ball_from = player.position + Vector2(12, -35)
			ball_end = Rooms.FIRST_FETCH if story.phase == Story.Phase.HOLD_FIRST else Rooms.LOST_BALL
			ball = ball_from
			ball_flight = 0
			_change(Story.Phase.FETCH_FIRST if story.phase == Story.Phase.HOLD_FIRST else Story.Phase.FETCH_SECOND)
		"Ask Kyoto": _ask_kyoto()
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
		"Enter the hall": _travel("hallway", Rooms.HALL_HOME + Vector2(25, 35))
		"Go home": _travel("apartment", Rooms.HOME_DOOR + Vector2(-45, 25))
		"Enter the garden": _travel("courtyard", Rooms.GARDEN_HOME + Vector2(45, 15))
		"Return to the hall": _travel("hallway", Rooms.HALL_EXIT + Vector2(-35, 25))
		"Fit the power cell":
			has_cell = false
			flags["powered"] = true
			found_at = Rooms.CART
			found_fx = 3
			sound.note(659.25, 1.0)
			_save()
		"Check the locked door", "Inspect the socket":
			flags["saw_socket"] = true
			inspect_fx = 4
			hint_icon = "cell"
			local_cue = Rooms.CART
			cue_time = 4
			sound.note(196, 0.25)
			_save()
		"Wake the little cart":
			found_at = Rooms.CART
			found_fx = 2
			sound.note(440, 0.5)
		"Inspect the seal":
			flags["saw_seal"] = true
			inspect_fx = 5
			hint_icon = "moons"
			sound.note(329.63, 0.7)
			_save()
		"Place the moon pieces":
			flags["greenhouse"] = true
			found_at = Rooms.GREENHOUSE
			found_fx = 4
			story.change(Story.Phase.COMPLETE)
			sound.note(659.25, 1.5, -12)
			_save()
			_show_menu("complete")
		"Look below": _show_menu("complete")
		"Pet Kyoto": _pet()
		_:
			if active_id != "": _collect(active_id)

func _collect(id: String) -> void:
	for obj in Rooms.objects(room):
		if obj.id != id: continue
		if found.has(id): return
		found[id] = true
		found_fx = 3.0
		found_at = obj.p
		if obj.type == "cell": has_cell = true
		sound.note(659.25 if obj.type == "moon" else 523.25, 0.8, -13)
		dog.heart_time = 2.5
		_save()
		return

func _ask_kyoto() -> void:
	idle_time = 0
	if room == "apartment" and story.phase == Story.Phase.STUCK and _near(Rooms.LOST_BALL,110):
		_begin_search()
		return
	for obj in Rooms.objects(room):
		if obj.hidden and not found.has(obj.id) and _near(obj.p, 110):
			revealed[obj.id] = true
			local_cue = obj.p
			cue_time = 5
			found_at = obj.p
			found_fx = 1.5
			dog_repath = 0
			sound.note(587.33, 0.4, -17)
			_save()
			return
	# A clue leads only a short distance; it does not expose the full map.
	var goal := _primary_target()
	var route := path_to(player.position, goal)
	local_cue = route[mini(route.size()-1, 12)] if not route.is_empty() else player.position
	cue_time = 5
	dog_repath = 0
	sound.note(440, 0.12, -21)

func _pet() -> void:
	if _near(dog.position, 72):
		dog.heart_time = 2.5
		story.pets += 1
		sound.note(523.25, 0.25, -22)
		_save()

func moon_count() -> int:
	return int(found.has("moon_home")) + int(found.has("moon_hall")) + int(found.has("moon_garden"))

func secret_count() -> int:
	var count := 0
	for name in ["toy","photo","cup","cassette","mail","toolbox","nest","seeds","arch"]:
		if found.has(name): count += 1
	return count

func _travel(destination: String, at: Vector2) -> void:
	if transitioning: return
	transitioning = true
	player_path.clear()
	player.moving = false
	var tween := create_tween()
	tween.tween_property(transition, "color:a", 1.0, 0.22)
	tween.tween_callback(func(): _apply_room(destination, at))
	tween.tween_property(transition, "color:a", 0.0, 0.3)
	tween.tween_callback(func(): transitioning = false)

func _apply_room(destination: String, at: Vector2) -> void:
	room = destination
	visited[room] = true
	_build_navigation()
	player.position = Vector2(nearest_cell(at)) * 12 + Vector2(6,6)
	dog.position = Vector2(nearest_cell(at + Vector2(32, 12))) * 12 + Vector2(6,6)
	player_path.clear()
	dog_path.clear()
	dog_repath = 0
	local_cue = Vector2.INF
	cue_time = 0
	idle_time = 0
	_camera_follow()
	camera.reset_smoothing()
	_save()

func _save() -> void:
	if test_mode: return
	var data: Dictionary = story.snapshot()
	data["version"] = 2
	data["room"] = room
	data["position"] = [player.position.x, player.position.y]
	data["found"] = found
	data["revealed"] = revealed
	data["flags"] = flags
	data["visited"] = visited
	data["cell"] = has_cell
	data["zoom"] = camera_zoom
	data["muted"] = sound.muted
	var file := FileAccess.open(WORLD_SAVE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		save_time = 1.8
	else: storage_available = false

func _saved_data() -> Dictionary:
	if FileAccess.file_exists(WORLD_SAVE):
		var data = JSON.parse_string(FileAccess.get_file_as_string(WORLD_SAVE))
		return data if data is Dictionary else {}
	return super._saved_data()

func _begin(restore_save: bool = false) -> void:
	story = Story.new()
	room = "apartment"
	flags = {}
	found = {}
	revealed = {}
	visited = {"apartment":true}
	has_cell = false
	player.position = Rooms.APARTMENT_START
	camera_zoom = 2.65
	if restore_save:
		var data := _saved_data()
		var old_version: int = int(data.get("version", 1))
		var story_data := data.duplicate(true)
		story_data["version"] = 1
		story.restore(story_data)
		if old_version == 2:
			room = data.get("room", "apartment")
			if not Rooms.TEXTURES.has(room): room = "apartment"
			found = data.get("found", {}) if data.get("found", {}) is Dictionary else {}
			revealed = data.get("revealed", {}) if data.get("revealed", {}) is Dictionary else {}
			flags = data.get("flags", {}) if data.get("flags", {}) is Dictionary else {}
			visited = data.get("visited", {}) if data.get("visited", {}) is Dictionary else {}
			has_cell = bool(data.get("cell",false))
			camera_zoom = clampf(float(data.get("zoom",2.65)),2.15,3.0)
			var coords = data.get("position", [])
			if coords is Array and coords.size() == 2 and (coords[0] is int or coords[0] is float) and (coords[1] is int or coords[1] is float):
				var p := Vector2(coords[0],coords[1])
				if walkable(p): player.position = p
		else:
			migrated = true
			if story.phase == Story.Phase.COMPLETE: story.change(Story.Phase.EXIT)
		sound.set_muted(bool(data.get("muted",false)))
	_build_navigation()
	if not walkable(player.position): player.position = Vector2(nearest_cell(Vector2(750,650))) * 12 + Vector2(6,6)
	dog.position = Vector2(nearest_cell(_dog_goal())) * 12 + Vector2(6,6)
	began = true
	departing = false
	transitioning = false
	ball_flight = -1
	dog_repath = 0
	cue_time = 0
	found_fx = 0
	inspect_fx = 0
	local_cue = Vector2.INF
	player_path.clear()
	_close_menu()
	_camera_follow()
	camera.reset_smoothing()
	sound.start()
	_save()

func _show_menu(kind: String) -> void:
	super._show_menu(kind)
	if kind == "title":
		menu.get_node("Shade").color.a = 0.5
		menu_eyebrow.text = "NEON AFTER HOURS / EXPLORATION BUILD"
		menu_subtitle.text = "ONE LAST WALK"
	if kind == "controls":
		menu_subtitle.text = "MOVE     Left stick / D-pad  ·  WASD / arrows\nINTERACT     A  ·  E / Space\nASK KYOTO / SNIFF     X  ·  Q\nPET KYOTO     Y  ·  F\nZOOM     LB / RB  ·  - / +\nPAUSE     Menu  ·  Esc\n\nDoors connect the areas. You can always return."
	if kind == "complete":
		menu_eyebrow.text = "BENEATH THE GREENHOUSE"
		menu_title.text = "Something is waking up…"
		menu_subtitle.text = "Exploration chapter complete · The datacenter is next."
		menu_buttons.get_child(0).text = "Keep exploring"
		menu_buttons.get_child(1).text = "Start a new walk"

func _explore_again() -> void:
	_close_menu()

func _update_hud() -> void:
	super._update_hud()
	chapter.text = Rooms.LABELS.get(room, "KYOTO")
	chapter.add_theme_font_size_override("font_size", 22)
	if is_instance_valid(inventory_label):
		inventory_label.text = "MOON PIECES  " + str(moon_count()) + " / 3" + ("    CELL" if has_cell else "")
		secrets_label.text = "Hidden finds  " + str(secret_count()) + " / 9"
	if interaction == "Ask Kyoto": prompt.text = "[ " + ("X" if using_pad else "Q") + " ]  Ask Kyoto"
	controls.text = "Move  L     Interact  A     Sniff  X     Pet  Y     Pause  Menu" if using_pad else "Move  WASD     Interact  E     Sniff  Q     Pet  F     Pause  Esc"

func _draw() -> void:
	draw_texture(Rooms.TEXTURES[room],Vector2.ZERO)
	if room == "apartment":
		for i in range(25):
			var x := 298 + fmod(i * 43.1, 300)
			var y := 135 + fmod(i * 18.3 + elapsed * 17, 89)
			draw_line(Vector2(x,y),Vector2(x-1,y+4),Color(0.65,0.8,1,0.15),0.5,true)
		if story.phase >= Story.Phase.SIGNAL:
			var p := Vector2(414,251)
			for i in range(4): draw_circle(p, 18+i*3, Color(0.3,0.75,1,0.025))
			draw_circle(p,13,MOON_COLOR)
			draw_circle(p+Vector2(6,-4),12,Color("1f243e"))
		if story.phase in [Story.Phase.FETCH_FIRST, Story.Phase.FETCH_SECOND] and (ball_flight >= 0 or story.phase == Story.Phase.FETCH_FIRST):
			draw_circle(ball,4,Color("e5d66c"))
			draw_arc(ball,3,-1.5,1.5,10,Color("fff0b4"),0.8,true)
		if story.phase in [Story.Phase.STUCK,Story.Phase.SEARCH]:
			for i in range(3):
				var p := Rooms.LOST_BALL+Vector2(-8+i*7,-12-sin(elapsed*5+i)*3)
				draw_line(p,p+Vector2(0,-5),Color("ecd5a0"),1,true)
		if found.has("toy"):
			var p := Vector2(412,800)+Vector2(sin(elapsed*1.4)*16,0)
			draw_circle(p,4,Color("ffc17b"))
			draw_circle(p+Vector2(-2,-1),0.8,Color("192133"))
			draw_circle(p+Vector2(2,-1),0.8,Color("192133"))
	if room == "hallway" and flags.get("powered",false):
		for i in range(3): draw_circle(Vector2(1123+i*13,307),2.5,Color("a0e5d0"))
		draw_line(Vector2(1274,411),Vector2(1398,419),Color(0.5,0.9,1,0.6),2)
	if room == "courtyard":
		for i in range(65):
			var p := Vector2(100+fmod(i*97.3,1340),300+fmod(i*71.7+elapsed*80,620))
			draw_line(p,p+Vector2(-1.8,9),Color(0.62,0.74,0.94,0.12),0.55,true)
		for i in range(moon_count()): draw_circle(Vector2(1114+i*24,305),6,MOON_COLOR)
		if flags.get("greenhouse",false):
			draw_colored_polygon(PackedVector2Array([Vector2(1080,348),Vector2(1202,352),Vector2(1250,437),Vector2(1040,429)]),Color(0.4,0.8,1,0.2))
	if not menu_open:
		if cue_time > 0 and local_cue != Vector2.INF: _draw_trail(player.position,local_cue)
		elif idle_time > 18:
			var route := path_to(player.position,_primary_target())
			if not route.is_empty(): _draw_trail(player.position,route[mini(route.size()-1,10)])
		for obj in Rooms.objects(room):
			if found.has(obj.id): continue
			if obj.hidden and not revealed.has(obj.id) and _near(obj.p,95):
				for j in range(3):
					var p := dog.position+Vector2(-4+j*4,-51-sin(elapsed*4+j)*2)
					draw_circle(p,1.0,Color("efd8a5"))
			elif _near(obj.p,75):
				draw_arc(obj.p,10+sin(elapsed*3)*2,0,TAU,24,Color(0.9,0.73,0.5,0.6),0.9,true)
	if found_fx > 0:
		var p := found_at+Vector2(0,-20-(3-found_fx)*9)
		draw_arc(p,8,0,TAU,26,Color(0.65,0.9,1,minf(1,found_fx)),1.4,true)
		for i in range(6):
			var offset := Vector2(cos(i*TAU/6+elapsed),sin(i*TAU/6+elapsed))*(14+(3-found_fx)*6)
			draw_circle(p+offset,1.1,Color(0.9,0.75,0.5,minf(1,found_fx)))
	if inspect_fx > 0:
		var p := player.position+Vector2(0,-112)
		if hint_icon == "cell":
			draw_rect(Rect2(p-Vector2(10,6),Vector2(20,12)),Color("f1c78b"),false,1.5)
			draw_line(p+Vector2(11,-2),p+Vector2(11,2),Color("f1c78b"),2)
		else:
			for i in range(3):
				draw_arc(p+Vector2((i-1)*15,0),5,0,TAU,20,MOON_COLOR,1,true)

func _run_smoke_test() -> void:
	_begin(false)
	_check(camera_zoom >= 2.6)
	_check(1536.0 / camera_zoom < 600)
	# A real playable floor, not a zoom on a postage-stamp map.
	_check(path_to(Rooms.APARTMENT_START,Rooms.LEASH).size() > 60)
	player.position = dog.position + Vector2(-40,0)
	_interact()
	_check(story.phase == Story.Phase.HOLD_FIRST)
	_interact()
	ball_flight = -1
	dog.position = Rooms.FIRST_FETCH
	_update_story(0.1)
	_check(story.phase == Story.Phase.RETURN_FIRST)
	dog.position = player.position+Vector2(38,9)
	_update_story(0.1)
	_interact()
	_interact()
	ball_flight = -1
	dog.position = Rooms.LOST_BALL+Vector2(18,19)
	_update_story(0.1)
	_check(story.phase == Story.Phase.STUCK)
	player.position = Vector2(475,415)
	_ask_kyoto()
	story.seconds = 3
	_update_story(0.1)
	_check(story.phase == Story.Phase.OFFER_ORB)
	dog.position = player.position+Vector2(35,0)
	_interact()
	_check(story.phase == Story.Phase.HOLD_ORB)
	player.position = Rooms.MONITOR
	_interact()
	story.seconds = 6
	_update_story(0.1)
	_check(story.phase == Story.Phase.LEASH)
	player.position = Rooms.LEASH
	_interact()
	_check(story.phase == Story.Phase.EXIT)
	# All room edges, objectives and hidden corners are reachable through navigation.
	for location in Rooms.TEXTURES.keys():
		room = location
		_build_navigation()
		var origin := Vector2(750,680)
		for obj in Rooms.objects(room):
			var route := path_to(origin,obj.p)
			_check(not route.is_empty())
			if not route.is_empty(): _check(route[-1].distance_to(obj.p) < 25)
		var doors: Array = [Rooms.HOME_DOOR,Rooms.MONITOR,Rooms.WORKBENCH] if room == "apartment" else ([Rooms.HALL_HOME,Rooms.HALL_EXIT,Rooms.CART] if room == "hallway" else [Rooms.GARDEN_HOME,Rooms.GREENHOUSE])
		for p in doors: _check(not path_to(origin,p).is_empty())
	_apply_room("hallway",Rooms.HALL_HOME)
	player.position = Rooms.HALL_EXIT
	_check(_find_interaction() == "Check the locked door")
	_apply_room("apartment",Rooms.WORKBENCH)
	_interact()
	_check(has_cell)
	_collect("moon_home")
	_apply_room("hallway",Rooms.CART)
	_interact()
	_check(flags.get("powered",false))
	_check(not has_cell)
	player.position = Vector2(1435,854)
	_check(_find_interaction() == "Ask Kyoto")
	_ask_kyoto()
	_check(revealed.has("moon_hall"))
	_interact()
	_check(found.has("moon_hall"))
	_apply_room("courtyard",Vector2(459,366))
	_interact()
	_check(moon_count() == 3)
	player.position = Rooms.GREENHOUSE
	_interact()
	_check(flags.get("greenhouse",false))
	_check(menu_kind == "complete")
	_explore_again()
	_check(not menu_open)
	_apply_room("hallway",Rooms.HALL_EXIT)
	_apply_room("apartment",Rooms.HOME_DOOR)
	_check(flags.get("powered",false) and moon_count() == 3)
	_check(not has_cell)
	if checks_failed:
		get_tree().quit(1)
		return
	print("PASS: scrolling world, opening, navigation to all rooms/objects, reversible connections, battery repair, sniff-gated discovery, moon seals, backtracking persistence")
	var tree := get_tree()
	queue_free()
	tree.create_timer(0.1).timeout.connect(tree.quit)
