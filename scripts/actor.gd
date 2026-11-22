extends Node2D
## Atlas regions remain in the original generated sheet. No runtime downloads.
const SHEET = preload("res://assets/characters.png")
var is_dog: bool = false
var moving: bool = false
var sitting: bool = false
var direction: Vector2 = Vector2.RIGHT
var clock: float = 0.0
var carrying: int = 0
var heart_time: float = 0.0

func _ready() -> void:
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; varying vec4 tint; void vertex(){tint=COLOR;} void fragment(){vec4 c=texture(TEXTURE, UV); c.a=smoothstep(0.14,0.72,c.a); COLOR=c*tint;}"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	material = mat

func tick(dt: float) -> void:
	clock += dt
	heart_time = maxf(0.0, heart_time - dt)
	z_index = int(position.y)
	queue_redraw()

func _draw() -> void:
	var breath: float = sin(clock * 2.4) * 1.1
	var bob: float = absf(sin(clock * 10.0)) * 3.0 if moving else breath
	var frame: int = (1 + int(clock * 7.0) % 2) if moving else 0
	if is_dog and sitting and not moving: frame = 3
	if not is_dog and direction.y < -0.5: frame = 3
	var flip: float = -1.0 if direction.x < -0.1 else 1.0
	# Soft layered contact shadow is always at the feet.
	for i in range(5):
		draw_set_transform(Vector2(0, -3), 0, Vector2(1, 0.24))
		draw_circle(Vector2.ZERO, (66.0 if is_dog else 40.0) - i * 4, Color(0.11, 0.055, 0.12, 0.06))
	draw_set_transform(Vector2(0, -bob), 0, Vector2(flip, 1))
	var cell: float = SHEET.get_width() / 4.0
	var src: Rect2
	var dst: Rect2
	if is_dog:
		src = Rect2(frame * cell, 710, cell, 380)
		dst = Rect2(-89, -164, 178, 174)
	else:
		src = Rect2(frame * cell, 80, cell, 485)
		dst = Rect2(-85, -258, 170, 263)
	draw_texture_rect_region(SHEET, dst, src)
	if carrying != 0:
		var p := Vector2(62, -99) if is_dog else Vector2(38, -112)
		var c := Color("9fe5ff") if carrying == 2 else Color("e5d66c")
		if carrying == 2:
			for i in range(5): draw_circle(p, 28 - i * 3, Color(0.3, 0.7, 1.0, 0.045))
		draw_circle(p, 13, c)
		draw_arc(p, 10, -1.5, 1.5, 14, Color(1, 1, 0.85, 0.65), 2, true)
		draw_circle(p + Vector2(-4, -5), 3, Color(1, 1, 1, 0.8))
	draw_set_transform(Vector2.ZERO)
	if heart_time > 0:
		for j in range(3):
			var p := Vector2(-30 + j * 28, -180 - (2.5 - heart_time) * 35 - (j % 2) * 15)
			var color := Color(1.0, 0.55, 0.51, minf(1.0, heart_time))
			draw_circle(p + Vector2(-4, 0), 5, color)
			draw_circle(p + Vector2(4, 0), 5, color)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-9, 1), p + Vector2(9, 1), p + Vector2(0, 12)]), color)
