extends Node2D

var score: float = 0.0
var game_over: bool = false
const STAGE2_SCORE: float = 279.0
var stage: int = 1
static var started: bool = false
static var music_stream: AudioStreamWAV = null

@onready var player: CharacterBody2D = $Player
@onready var spawner: Node = $Spawner
@onready var score_label: Label = $CanvasLayer/ScoreLabel
@onready var game_over_panel: Panel = $CanvasLayer/GameOverPanel
@onready var final_score_label: Label = $CanvasLayer/GameOverPanel/FinalScoreLabel
@onready var retry_button: Button = $CanvasLayer/GameOverPanel/RetryButton
@onready var start_screen: Control = $CanvasLayer/StartScreen
@onready var play_button: Button = $CanvasLayer/StartScreen/PlayButton

func _ready() -> void:
    RenderingServer.set_default_clear_color(Color(0.04, 0.02, 0.13, 1))
    retry_button.pressed.connect(_restart_game)
    spawner.connect("obstacle_spawned", Callable(self, "_on_obstacle_spawned"))
    game_over_panel.visible = false
    play_button.pressed.connect(_start_game)
    $GameOverSound.stream = _make_game_over_sound()
    var mp3_path := "res://assets/cube_run_music.mp3"
    if ResourceLoader.exists(mp3_path):
        var mp3 = load(mp3_path)
        if mp3 is AudioStreamMP3:
            mp3.loop = true
            $Music.stream = mp3
    if $Music.stream == null:
        if music_stream == null:
            music_stream = _make_music()
        $Music.stream = music_stream
    if started:
        $Music.play()
    if started:
        start_screen.visible = false
    else:
        start_screen.visible = true
        get_tree().paused = true

func _make_game_over_sound() -> AudioStreamWAV:
    var rate := 22050
    var n := int(rate * 0.9)
    var data := PackedByteArray()
    data.resize(n * 2)
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    var phase := 0.0
    var phase2 := 0.0
    var noise_val := 0.0
    for i in n:
        var t := float(i) / float(rate)
        var f := roundf((880.0 * exp(-t * 3.6) + 70.0) / 20.0) * 20.0
        phase += f / float(rate)
        phase2 += f * 0.5 / float(rate)
        var env := exp(-t * 3.2)
        var s := (1.0 if fmod(phase, 1.0) < 0.5 else -1.0) * env * 0.5
        s += (1.0 if fmod(phase2, 1.0) < 0.5 else -1.0) * env * 0.25
        if i % 6 == 0:
            noise_val = rng.randf_range(-1.0, 1.0)
        s += noise_val * exp(-t * 14.0) * 0.7
        if t > 0.75:
            s *= clampf(1.0 - (t - 0.75) / 0.15, 0.0, 1.0)
        s = roundf(s * 7.0) / 7.0
        s = clampf(s * 0.8, -1.0, 1.0)
        data.encode_s16(i * 2, int(s * 32767.0))
    var wav := AudioStreamWAV.new()
    wav.format = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = rate
    wav.stereo = false
    wav.data = data
    return wav

func _make_music() -> AudioStreamWAV:
    var rate := 11025
    var bpm := 140.0
    var beat := 60.0 / bpm
    var step_len := beat / 4.0
    var bars := 4
    var n := int(float(rate) * beat * 4.0 * float(bars))
    var data := PackedByteArray()
    data.resize(n * 2)
    var roots := [55.0, 43.65, 65.41, 49.0]
    var arps := [
        [1.0, 1.189, 1.498, 2.0],
        [1.0, 1.26, 1.498, 2.0],
        [1.0, 1.26, 1.498, 2.0],
        [1.0, 1.26, 1.498, 2.0],
    ]
    var rng := RandomNumberGenerator.new()
    rng.seed = 11
    var noise_a := 0.0
    var noise_b := 0.0
    for i in n:
        var t := float(i) / float(rate)
        var step := int(t / step_len)
        var st := t - float(step) * step_len
        var bar := int(float(step) / 16.0) % bars
        var s16 := step % 16
        var bt := fmod(t, beat)
        var bi := int(t / beat) % 4
        var root: float = roots[bar]
        if i % 3 == 0:
            noise_a = rng.randf_range(-1.0, 1.0)
        if i % 2 == 0:
            noise_b = rng.randf_range(-1.0, 1.0)
        # kick
        var s := sin(TAU * (45.0 * bt + 2.5 * (1.0 - exp(-30.0 * bt)))) * exp(-bt * 12.0) * 0.9
        # snare / clap
        if bi == 1 or bi == 3:
            s += noise_a * exp(-bt * 16.0) * 0.4
        # hi-hat
        var half := beat / 2.0
        var ht := fmod(t, half)
        var off := int(t / half) % 2
        s += noise_b * exp(-ht * 70.0) * (0.22 if off == 1 else 0.1)
        # sidechain duck
        var duck := 1.0 - 0.85 * exp(-bt * 9.0)
        # bass (octave bounce)
        var bf := root * (2.0 if s16 % 4 == 2 else 1.0)
        var bp := fmod(bf * t, 1.0)
        var bass := (1.0 if bp < 0.5 else -1.0) * 0.5 + (2.0 * bp - 1.0) * 0.5
        s += bass * clampf(1.0 - st / step_len * 0.4, 0.0, 1.0) * 0.45 * duck
        # lead arpeggio (25% pulse)
        var arp: Array = arps[bar]
        var lf: float = root * float(arp[s16 % 4]) * 4.0
        var lp := fmod(lf * t, 1.0)
        s += (1.0 if lp < 0.25 else -1.0) * exp(-st * 14.0) * 0.2 * duck
        s = tanh(s * 0.9)
        data.encode_s16(i * 2, int(s * 30000.0))
    var wav := AudioStreamWAV.new()
    wav.format = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = rate
    wav.stereo = false
    wav.data = data
    wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
    wav.loop_begin = 0
    wav.loop_end = n
    return wav

func _start_game() -> void:
    started = true
    start_screen.visible = false
    $Music.play()
    get_tree().paused = false

func _process(delta: float) -> void:
    if game_over:
        return
    score += delta * 10.0
    score_label.text = "النقاط: " + str(int(score))
    if stage == 1 and score >= STAGE2_SCORE:
        _enter_stage_2()

func _theme_obstacle(obstacle: Node) -> void:
    obstacle.get_node("Visual").set("color", Color(0.02, 0.02, 0.02, 1))
    obstacle.get_node("Glow").set("color", Color(1.0, 0.8, 0.0, 0.95))

func _enter_stage_2() -> void:
    stage = 2
    RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.0, 1))
    for child in get_children():
        var n := String(child.name)
        if n.begins_with("BgShape") or n.begins_with("BgTri"):
            child.set("color", Color(1.0, 0.78, 0.0, 0.16))
        elif n.begins_with("RingGlow"):
            child.set("default_color", Color(1.0, 0.8, 0.0, 0.3))
        elif n.begins_with("Ring"):
            child.set("default_color", Color(1.0, 0.95, 0.4, 1.0))
    $Ground/GroundVisual.set("color", Color(1.0, 0.8, 0.0, 1.0))
    $Ground/FloorGlow.set("color", Color(1.0, 0.95, 0.5, 1.0))
    $Player/Visual.set("color", Color(1.0, 0.85, 0.05, 1.0))
    spawner.set("obstacle_speed", 440.0)
    spawner.set("min_delay", 0.9)
    spawner.set("max_delay", 1.5)
    for obstacle in get_tree().get_nodes_in_group("obstacles"):
        _theme_obstacle(obstacle)
    _switch_music_stage_2()
    _show_stage_banner()

func _switch_music_stage_2() -> void:
    var path := "res://assets/stage2_music.mp3"
    var stream2: AudioStream = null
    if ResourceLoader.exists(path):
        var loaded = load(path)
        if loaded is AudioStreamMP3:
            loaded.loop = true
            stream2 = loaded
    $Music.stop()
    if stream2 != null:
        $Music.stream = stream2
        $Music.pitch_scale = 1.0
    else:
        $Music.pitch_scale = 1.2
    $Music.play()

func _show_stage_banner() -> void:
    var banner := Label.new()
    banner.text = "المرحلة 2"
    banner.add_theme_font_size_override("font_size", 56)
    banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0, 1.0))
    banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    banner.position = Vector2(280, 120)
    banner.size = Vector2(400, 80)
    $CanvasLayer.add_child(banner)
    var tw := create_tween()
    tw.tween_interval(1.2)
    tw.tween_property(banner, "modulate:a", 0.0, 1.0)
    tw.tween_callback(banner.queue_free)

func _unhandled_key_input(event: InputEvent) -> void:
    if game_over and event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_R or event.keycode == KEY_ENTER:
            _restart_game()

func _on_obstacle_spawned(obstacle: Area2D) -> void:
    if stage == 2:
        _theme_obstacle(obstacle)
    obstacle.connect("hit_player", Callable(self, "_end_game"))

func _end_game() -> void:
    if game_over:
        return
    game_over = true
    player.stop_player()
    spawner.call("stop_spawning")
    for obstacle in get_tree().get_nodes_in_group("obstacles"):
        obstacle.set_process(false)
    $Music.stop()
    $GameOverSound.play()
    game_over_panel.visible = true
    final_score_label.text = "النقاط: " + str(int(score))

func _restart_game() -> void:
    get_tree().reload_current_scene()
