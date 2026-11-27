extends Node
## Menu playback lives outside the mission audio session.

const THEMES: Array[AudioStream] = [
	preload("res://assets/audio/local/music/menu_theme_a_the_sleeping_evil.ogg"),
	preload("res://assets/audio/local/music/menu_theme_b_the_last_prayer.ogg"),
	preload("res://assets/audio/local/music/menu_theme_c_the_ancient_hunger.ogg"),
]
const START_FADE := 1.25
const CROSSFADE := 5.0
const EXIT_FADE := 0.7

@onready var _music: Array[AudioStreamPlayer] = [$MusicA, $MusicB]
@onready var _click: AudioStreamPlayer = $Click
var _rng := RandomNumberGenerator.new()
var _remaining: Array[AudioStream] = []
var _last_theme: AudioStream
var _current := 0
var _active := false
var _fade: Tween


func _ready() -> void:
	_rng.randomize()
	for player in _music:
		player.volume_linear = 0.0
	set_process(false)


func play_click() -> void:
	_click.play()


func set_music_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	set_process(active)
	if not active:
		_fade_to(null, EXIT_FADE)
	elif _music[_current].playing:
		_fade_to(_music[_current], START_FADE)
	else:
		_start_next(START_FADE)


func _process(_delta: float) -> void:
	if _fade != null and _fade.is_running():
		return
	var player := _music[_current]
	if not player.playing:
		_start_next(START_FADE)
	elif player.stream.get_length() - player.get_playback_position() <= CROSSFADE:
		_start_next(CROSSFADE)


func _take_next_theme() -> AudioStream:
	var refilling := _remaining.is_empty()
	if refilling:
		_remaining.assign(THEMES)
		_remaining.erase(_last_theme)
	var theme: AudioStream = _remaining.pop_at(_rng.randi_range(0, _remaining.size() - 1))
	if refilling and _last_theme != null:
		_remaining.append(_last_theme)
	_last_theme = theme
	return theme


func _start_next(seconds: float) -> void:
	_current = 1 - _current
	var player := _music[_current]
	player.stream = _take_next_theme()
	player.volume_linear = 0.0
	player.play()
	_fade_to(player, seconds)


func _fade_to(target: AudioStreamPlayer, seconds: float) -> void:
	if _fade != null:
		_fade.kill()
	var start_gain := Vector2(_music[0].volume_linear, _music[1].volume_linear)
	var target_gain := Vector2(float(_music[0] == target), float(_music[1] == target))
	_fade = create_tween()
	_fade.tween_method(_mix_music.bind(start_gain, target_gain), 0.0, 1.0, seconds)
	_fade.tween_callback(func() -> void:
		for player in _music:
			if player != target:
				player.stop()
				player.stream = null)


func _mix_music(progress: float, start_gain: Vector2, target_gain: Vector2) -> void:
	# Interpolate power so both themes keep their combined level across the overlap.
	var weight := pow(sin(progress * PI * 0.5), 2.0)
	var power := (start_gain * start_gain).lerp(target_gain * target_gain, weight)
	_music[0].volume_linear = sqrt(power.x)
	_music[1].volume_linear = sqrt(power.y)
