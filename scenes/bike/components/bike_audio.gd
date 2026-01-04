class_name BikeAudio extends Node

# Shared state
var state: BikeState
var bike_gearing: BikeGearing

# Local state

@onready var engine_sound: AudioStreamPlayer = null
@onready var tire_screech: AudioStreamPlayer = null
@onready var engine_grind: AudioStreamPlayer = null
@onready var exhaust_pops: AudioStreamPlayer = null

# Audio settings
@export var engine_min_pitch: float = 0.25
@export var engine_max_pitch: float = 2.2
@export var engine_boost_max_pitch: float = 2.4
@export var gear_grind_volume: float = 0.3
@export var stoppie_volume: float = 0.4
@export var fishtail_volume: float = 0.4

# Exhaust pop settings
@export var exhaust_pop_threshold: float = 0.7  # RPM ratio above which pops can occur
@export var exhaust_pop_chance: float = 0.15    # Chance per frame when conditions met
@export var exhaust_pop_volume: float = 0.2
@export var exhaust_pop_cooldown: float = 0.2   # Min time between pops

# Input state (from signals)
var throttle: float = 0.0

# Exhaust pop tracking
var last_rpm_ratio: float = 0.0
var exhaust_pop_timer: float = 0.0

func _bike_setup(bike_state: BikeState, bike_input: BikeInput, gearing: BikeGearing,
        engine: AudioStreamPlayer, screech: AudioStreamPlayer,
        grind: AudioStreamPlayer, pops: AudioStreamPlayer):
    state = bike_state
    bike_gearing = gearing

    engine_sound = engine
    tire_screech = screech
    engine_grind = grind
    exhaust_pops = pops

    bike_input.throttle_changed.connect(func(v): throttle = v)
    state.state_changed.connect(_on_state_changed)


func _bike_update(delta):
    match state.player_state:
        BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED:
            return  # Audio handled by state change callback
        _:
            update_engine_audio(delta, bike_gearing.get_rpm_ratio())


func _on_state_changed(old_state: BikeState.PlayerState, new_state: BikeState.PlayerState):
    # Handle state exit
    match old_state:
        BikeState.PlayerState.TRICK_GROUND:
            stop_tire_screech()

    # Handle state entry
    match new_state:
        BikeState.PlayerState.CRASHING:
            stop_engine()
            # Tire screech handled by crash signal in player_controller
        BikeState.PlayerState.CRASHED:
            stop_tire_screech()


func update_engine_audio(delta: float, rpm_ratio: float):
    if !engine_sound:
        return

    if state.is_stalled:
        if engine_sound.playing:
            engine_sound.stop()
        _stop_exhaust_pops()
        last_rpm_ratio = 0.0
        return

    if state.speed > 0.5 or throttle > 0:
        if !engine_sound.playing:
            engine_sound.play()

        var max_pitch = engine_boost_max_pitch if state.is_boosting else engine_max_pitch
        var target_pitch = lerpf(engine_min_pitch, max_pitch, clamp(rpm_ratio, 0.0, 1.0))
        engine_sound.pitch_scale = target_pitch
    else:
        if engine_sound.playing:
            engine_sound.stop()

    # Exhaust pops when RPM drops from high revs (engine braking / letting off throttle)
    exhaust_pop_timer -= delta
    if exhaust_pop_timer <= 0.0:
        var rpm_dropping = rpm_ratio < last_rpm_ratio
        var was_high_rpm = last_rpm_ratio > exhaust_pop_threshold
        if rpm_dropping and was_high_rpm and randf() < exhaust_pop_chance:
            _play_exhaust_pop()
            exhaust_pop_timer = exhaust_pop_cooldown

    last_rpm_ratio = rpm_ratio


func on_gear_changed():
    # Stop pops when shifting to a new gear
    _stop_exhaust_pops()


func _play_exhaust_pop():
    if !exhaust_pops:
        return
    exhaust_pops.volume_db = linear_to_db(exhaust_pop_volume)
    exhaust_pops.pitch_scale = randf_range(0.8, 1.2)
    exhaust_pops.play()


func _stop_exhaust_pops():
    if !exhaust_pops:
        return
    if exhaust_pops.playing:
        exhaust_pops.stop()


func play_tire_screech(volume: float):
    if !tire_screech:
        return
    if !tire_screech.playing:
        tire_screech.volume_db = linear_to_db(volume)
        tire_screech.play()


func stop_tire_screech():
    if !tire_screech:
        return
    if tire_screech.playing:
        tire_screech.stop()


func play_gear_grind():
    if !engine_grind:
        return
    engine_grind.volume_db = linear_to_db(gear_grind_volume)
    engine_grind.play()


func stop_engine():
    if !engine_sound:
        return
    if engine_sound.playing:
        engine_sound.stop()


func _bike_reset():
    stop_engine()
    stop_tire_screech()
    _stop_exhaust_pops()

