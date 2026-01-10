class_name BikeAudio extends BikeComponent

# Audio settings (local config)
@export var gear_grind_volume: float = 0.3
@export var stoppie_volume: float = 0.4
@export var fishtail_volume: float = 0.4

# Exhaust pop settings
@export var exhaust_pop_threshold: float = 0.7 # RPM ratio above which pops can occur
@export var exhaust_pop_chance: float = 0.15 # Chance per frame when conditions met
@export var exhaust_pop_volume: float = 0.2
@export var exhaust_pop_cooldown: float = 0.2 # Min time between pops

# Exhaust pop tracking
var last_rpm_ratio: float = 0.0
var exhaust_pop_timer: float = 0.0

func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller

    player_controller.state.state_changed.connect(_on_state_changed)
    player_controller.bike_crash.crashed.connect(_on_crashed)

    # Gearing signals
    player_controller.bike_gearing.gear_grind.connect(play_gear_grind)
    player_controller.bike_gearing.gear_changed.connect(on_gear_changed)
    player_controller.bike_gearing.engine_stalled.connect(stop_engine)

    # Tricks signals
    player_controller.bike_tricks.tire_screech_start.connect(play_tire_screech)
    player_controller.bike_tricks.tire_screech_stop.connect(stop_tire_screech)
    player_controller.bike_tricks.boost_started.connect(play_nos)
    player_controller.bike_tricks.boost_ended.connect(stop_nos)


func _bike_update(delta):
    match player_controller.state.player_state:
        BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED:
            return # Audio handled by state change callback
        _:
            update_engine_audio(delta, player_controller.state.rpm_ratio)


func _on_state_changed(old_state: BikeState.PlayerState, new_state: BikeState.PlayerState):
    # Handle state exit
    match old_state:
        BikeState.PlayerState.TRICK_GROUND:
            stop_tire_screech()

    # Handle state entry
    match new_state:
        BikeState.PlayerState.CRASHING:
            stop_engine()
        BikeState.PlayerState.CRASHED:
            stop_tire_screech()


func _on_crashed(_pitch_dir: float, lean_dir: float):
    # Play tire screech for lowside crashes
    if lean_dir != 0:
        play_tire_screech(1.0)


func update_engine_audio(delta: float, rpm_ratio: float):
    if !player_controller.engine_sound:
        return

    if player_controller.state.is_stalled:
        if player_controller.engine_sound.playing:
            player_controller.engine_sound.stop()
        _stop_exhaust_pops()
        last_rpm_ratio = 0.0
        return

    if player_controller.state.speed > 0.5 or player_controller.bike_input.throttle > 0:
        if !player_controller.engine_sound.playing:
            player_controller.engine_sound.play()

        var br := player_controller.bike_resource
        var max_pitch = br.engine_boost_max_pitch if player_controller.state.is_boosting else br.engine_max_pitch
        var target_pitch = lerpf(br.engine_min_pitch, max_pitch, clamp(rpm_ratio, 0.0, 1.0))
        player_controller.engine_sound.pitch_scale = target_pitch
    else:
        if player_controller.engine_sound.playing:
            player_controller.engine_sound.stop()

    # Exhaust pops when RPM drops from high revs (engine braking / letting off throttle)
    exhaust_pop_timer -= delta
    if exhaust_pop_timer <= 0.0:
        var rpm_dropping = rpm_ratio < last_rpm_ratio
        var was_high_rpm = last_rpm_ratio > exhaust_pop_threshold
        if rpm_dropping and was_high_rpm and randf() < exhaust_pop_chance:
            _play_exhaust_pop()
            exhaust_pop_timer = exhaust_pop_cooldown

    last_rpm_ratio = rpm_ratio


func on_gear_changed(_new_gear: int):
    # Stop pops when shifting to a new gear
    _stop_exhaust_pops()


func _play_exhaust_pop():
    if !player_controller.exhaust_pops:
        return
    player_controller.exhaust_pops.volume_db = linear_to_db(exhaust_pop_volume)
    player_controller.exhaust_pops.pitch_scale = randf_range(0.8, 1.2)
    player_controller.exhaust_pops.play()


func _stop_exhaust_pops():
    if !player_controller.exhaust_pops:
        return
    if player_controller.exhaust_pops.playing:
        player_controller.exhaust_pops.stop()


func play_tire_screech(volume: float):
    if !player_controller.tire_screech:
        return
    if !player_controller.tire_screech.playing:
        player_controller.tire_screech.volume_db = linear_to_db(volume)
        player_controller.tire_screech.play()


func stop_tire_screech():
    if !player_controller.tire_screech:
        return
    if player_controller.tire_screech.playing:
        player_controller.tire_screech.stop()


func play_gear_grind():
    if !player_controller.engine_grind:
        return
    player_controller.engine_grind.volume_db = linear_to_db(gear_grind_volume)
    player_controller.engine_grind.play()


func stop_engine():
    if !player_controller.engine_sound:
        return
    if player_controller.engine_sound.playing:
        player_controller.engine_sound.stop()


func play_nos():
    if !player_controller.nos_sound:
        return
    if !player_controller.nos_sound.playing:
        player_controller.nos_sound.play()


func stop_nos():
    if !player_controller.nos_sound:
        return
    if player_controller.nos_sound.playing:
        player_controller.nos_sound.stop()


func _bike_reset():
    stop_engine()
    stop_tire_screech()
    _stop_exhaust_pops()
    stop_nos()
