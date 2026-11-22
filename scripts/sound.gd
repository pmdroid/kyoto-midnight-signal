extends Node
var muted: bool = false
var music: AudioStreamPlayer
var effects: Array[AudioStreamPlayer] = []
var next_voice: int = 0
var tones: Dictionary = {}

func _ready() -> void:
	music = AudioStreamPlayer.new()
	music.stream = preload("res://assets/audio/room.wav")
	music.volume_db = -19
	add_child(music)
	for i in range(5):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -15
		add_child(voice)
		effects.append(voice)

func start() -> void:
	if not music.playing: music.play()

func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(0, value)

func note(freq: float, duration: float = 0.35, volume: float = -15.0) -> void:
	var key := str(freq) + ":" + str(duration)
	if not tones.has(key):
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		var count := int(duration * 22050)
		var bytes := PackedByteArray()
		bytes.resize(count * 2)
		for i in range(count):
			var t: float = float(i) / 22050.0
			var envelope: float = minf(1.0, t / 0.012) * exp(-t * 7.0 / duration)
			var value: float = (sin(TAU * freq * t) + 0.18 * sin(TAU * freq * 2.0 * t)) * envelope
			bytes.encode_s16(i * 2, int(value * 16000.0))
		stream.data = bytes
		tones[key] = stream
	var voice: AudioStreamPlayer = effects[next_voice]
	next_voice = (next_voice + 1) % effects.size()
	voice.stream = tones[key]
	voice.volume_db = volume
	voice.play()
