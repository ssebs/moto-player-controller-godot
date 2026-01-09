class_name BikeGearing extends BikeComponent

signal gear_changed(new_gear: int)
signal engine_stalled
signal engine_started
signal gear_grind # Tried to shift without clutch


# Gear system
@export var num_gears: int = 6
@export var max_rpm: float = 11000.0
@export var idle_rpm: float = 1000.0
@export var stall_rpm: float = 800.0
@export var gear_ratios: Array[float] = [2.92, 2.05, 1.6, 1.46, 1.15, 1.0] # IRL ninja 500

# Clutch tuning
@export var clutch_engage_speed: float = 6.0 # How fast clutch pulls in when held
@export var clutch_release_speed: float = 2.5 # How fast clutch releases when not held
@export var clutch_tap_amount: float = 0.35 # How much a tap adds to clutch value
@export var clutch_hold_delay: float = 0.05 # Seconds before hold starts engaging fully
@export var gear_shift_threshold: float = 0.2 # Clutch value needed to shift
@export var rpm_blend_speed: float = 12.0 # How fast RPM changes when clutch engaged
@export var rev_match_speed: float = 8.0 # How fast RPM adjusts during easy mode shifts

# Auto-shift tuning (during boost)
@export var auto_shift_up_rpm: float = 0.85 # RPM ratio to shift up
@export var auto_shift_down_rpm: float = 0.35 # RPM ratio to shift down

# Rev limiter
@export var redline_cut_amount: float = 1000.0 # RPM drop when hitting limiter
@export var redline_threshold: float = 200.0 # How close to max_rpm before limiter kicks in

# Input state (from signals - clutch needs special handling)
var clutch_held: bool = false
var clutch_just_pressed: bool = false

# Local state
var clutch_hold_time: float = 0.0


func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller

    player_controller.bike_input.clutch_held_changed.connect(_on_clutch_input)
    player_controller.bike_input.gear_up_pressed.connect(_on_gear_up)
    player_controller.bike_input.gear_down_pressed.connect(_on_gear_down)

func _bike_update(delta):
    match player_controller.state.player_state:
        BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED:
            # Engine stalls during crash
            if not player_controller.state.is_stalled:
                player_controller.state.is_stalled = true
                engine_stalled.emit()
            player_controller.state.rpm_ratio = 0.0
            return
        _:
            # Engine runs normally in all other states
            update_clutch(delta)
            update_rpm(delta)
            # Cache RPM ratio for other components to use
            player_controller.state.rpm_ratio = get_rpm_ratio()
            # Auto-shift during boost or easy mode
            if player_controller.state.is_boosting or player_controller.state.difficulty == player_controller.state.PlayerDifficulty.EASY:
                _update_auto_shift()

func _on_clutch_input(held: bool, just_pressed: bool):
    clutch_held = held
    clutch_just_pressed = just_pressed


func _on_gear_up():
    # Easy mode: auto-shift handles this, ignore manual input
    if player_controller.state.difficulty == player_controller.state.PlayerDifficulty.EASY:
        return
    # Medium: no clutch needed, Hard: clutch required
    var can_shift = player_controller.state.difficulty == player_controller.state.PlayerDifficulty.MEDIUM or player_controller.state.clutch_value > gear_shift_threshold
    if can_shift:
        if player_controller.state.current_gear < num_gears:
            player_controller.state.current_gear += 1
            gear_changed.emit(player_controller.state.current_gear)
    else:
        gear_grind.emit()


func _on_gear_down():
    # Easy mode: auto-shift handles this, ignore manual input
    if player_controller.state.difficulty == player_controller.state.PlayerDifficulty.EASY:
        return
    # Medium: no clutch needed, Hard: clutch required
    var can_shift = player_controller.state.difficulty == player_controller.state.PlayerDifficulty.MEDIUM or player_controller.state.clutch_value > gear_shift_threshold
    if can_shift:
        if player_controller.state.current_gear > 1:
            player_controller.state.current_gear -= 1
            gear_changed.emit(player_controller.state.current_gear)
    else:
        gear_grind.emit()


func update_clutch(delta: float):
    if clutch_held:
        clutch_hold_time += delta
        if clutch_just_pressed:
            # Tap: instantly add to clutch value
            player_controller.state.clutch_value = minf(player_controller.state.clutch_value + clutch_tap_amount, 1.0)
        elif clutch_hold_time >= clutch_hold_delay:
            # Held past delay: pull in fully
            player_controller.state.clutch_value = move_toward(player_controller.state.clutch_value, 1.0, clutch_engage_speed * delta)
    else:
        clutch_hold_time = 0.0
        # Release: slowly let clutch out
        player_controller.state.clutch_value = move_toward(player_controller.state.clutch_value, 0.0, clutch_release_speed * delta)


func get_clutch_engagement() -> float:
    """Returns 0-1 where 0 = clutch pulled in (disengaged), 1 = clutch released (engaged to wheel)"""
    return 1.0 - player_controller.state.clutch_value


func get_max_speed_for_gear() -> float:
    var gear_ratio = gear_ratios[player_controller.state.current_gear - 1]
    var lowest_ratio = gear_ratios[num_gears - 1]
    return player_controller.bike_physics.max_speed * (lowest_ratio / gear_ratio)


func update_rpm(delta: float):
    var is_easy_mode := player_controller.state.difficulty == player_controller.state.PlayerDifficulty.EASY

    if player_controller.state.is_stalled:
        player_controller.state.current_rpm = 0.0
        var should_start = false
        # Restart engine with throttle + clutch while stalled
        if player_controller.state.clutch_value > 0.5 and player_controller.bike_input.throttle > 0.3:
            should_start = true
        # Easy mode: auto-start with throttle only (no clutch required)
        if is_easy_mode and player_controller.bike_input.throttle > 0.1:
            should_start = true
        
        if should_start:
            player_controller.state.is_stalled = false
            player_controller.state.current_rpm = idle_rpm
            engine_started.emit()
        return

    var engagement = get_clutch_engagement()

    # Calculate wheel-driven RPM based on wheel speed
    var gear_max_speed = get_max_speed_for_gear()
    var speed_ratio = player_controller.state.speed / gear_max_speed if gear_max_speed > 0 else 0.0
    var wheel_rpm = speed_ratio * max_rpm

    # Throttle-driven RPM (instant - no smoothing, engine revs freely)
    var throttle_rpm = lerpf(idle_rpm, max_rpm, player_controller.bike_input.throttle)

    # Easy mode: automatic clutch - disengage when stationary/slow to allow revving
    if is_easy_mode and player_controller.state.speed < 5.0:
        engagement = clamp(player_controller.state.speed / 5.0, 0.0, 1.0)

    # Blend between throttle RPM and wheel RPM based on clutch engagement
    # engagement = 0: clutch in, engine free-revs (fast response)
    # engagement = 1: clutch out, engine locked to wheel (follows wheel speed)
    var target_rpm = lerpf(throttle_rpm, wheel_rpm, engagement)

    # When clutch is fully engaged, RPM follows wheel speed
    if engagement > 0.95:
        if player_controller.state.difficulty != player_controller.state.PlayerDifficulty.HARD:
            # Easy/Medium: smooth rev-matching when shifting (RPM blends to new gear's wheel RPM)
            player_controller.state.current_rpm = lerpf(player_controller.state.current_rpm, wheel_rpm, rev_match_speed * delta)
        else:
            # Hard: RPM locked directly to wheel speed
            player_controller.state.current_rpm = wheel_rpm
    else:
        # RPM blend speed: fast when free-revving, slower when engaged to wheel
        var blend_speed = lerpf(12.0, rpm_blend_speed, engagement)
        player_controller.state.current_rpm = lerpf(player_controller.state.current_rpm, target_rpm, blend_speed * delta)

    # Check for stall when clutch is mostly engaged and RPM too low (skip on easy mode)
    if not is_easy_mode and engagement > 0.9 and player_controller.state.current_rpm < stall_rpm:
        player_controller.state.is_stalled = true
        player_controller.state.current_gear = 1
        engine_stalled.emit()
        return

    # Rev limiter: cut RPM when at redline with throttle (creates oscillation)
    var limiter_point = max_rpm - redline_threshold
    if player_controller.state.current_rpm >= limiter_point and player_controller.bike_input.throttle > 0.5:
        player_controller.state.current_rpm = limiter_point - redline_cut_amount

    player_controller.state.current_rpm = clamp(player_controller.state.current_rpm, idle_rpm, max_rpm)

func get_rpm_ratio() -> float:
    if max_rpm <= idle_rpm:
        return 0.0
    return (player_controller.state.current_rpm - idle_rpm) / (max_rpm - idle_rpm)


func _update_auto_shift():
    var rpm_ratio = get_rpm_ratio()
    if rpm_ratio >= auto_shift_up_rpm and player_controller.state.current_gear < num_gears:
        player_controller.state.current_gear += 1
        gear_changed.emit(player_controller.state.current_gear)
    elif rpm_ratio <= auto_shift_down_rpm and player_controller.state.current_gear > 1:
        player_controller.state.current_gear -= 1
        gear_changed.emit(player_controller.state.current_gear)


func get_power_output() -> float:
    """Returns power multiplier based on current RPM and gear"""
    if player_controller.state.is_stalled:
        return 0.0

    var engagement = get_clutch_engagement()
    if player_controller.state.difficulty == player_controller.state.PlayerDifficulty.EASY:
        engagement = 1.0
    elif engagement < 0.05:
        return 0.0

    var rpm_ratio = get_rpm_ratio()
    var power_curve = rpm_ratio * (2.0 - rpm_ratio) # Peaks around 75% RPM

    var gear_ratio = gear_ratios[player_controller.state.current_gear - 1]
    var base_ratio = gear_ratios[num_gears - 1]
    var torque_multiplier = gear_ratio / base_ratio

    var effective_throttle = player_controller.bike_tricks.get_boosted_throttle(player_controller.bike_input.throttle)
    return effective_throttle * power_curve * torque_multiplier * engagement


func is_clutch_dump(last_clutch: float) -> bool:
    """Returns true if clutch was just dumped while revving"""
    return last_clutch > 0.7 and player_controller.state.clutch_value < 0.3 and player_controller.bike_input.throttle > 0.5


func _bike_reset():
    player_controller.state.current_gear = 1
    player_controller.state.current_rpm = idle_rpm
    player_controller.state.is_stalled = false
    player_controller.state.clutch_value = 0.0
    clutch_hold_time = 0.0
