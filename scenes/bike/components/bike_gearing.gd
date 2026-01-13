class_name BikeGearing extends BikeComponent

signal gear_changed(new_gear: int)
signal engine_stalled
signal engine_started
signal gear_grind # Tried to shift without clutch


# Local config (not in BikeResource)
@export var gear_shift_threshold: float = 0.2 # Clutch value needed to shift
@export var auto_shift_up_rpm: float = 0.85 # RPM ratio to shift up
@export var auto_shift_down_rpm: float = 0.35 # RPM ratio to shift down

# Input state (from signals - clutch needs special handling)
var clutch_held: bool = false
var clutch_just_pressed: bool = false

# Local state
var clutch_hold_time: float = 0.0

#region BikeComponent lifecycle
func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller

    player_controller.bike_input.clutch_held_changed.connect(_on_clutch_input)
    player_controller.bike_input.gear_up_pressed.connect(_on_gear_up)
    player_controller.bike_input.gear_down_pressed.connect(_on_gear_down)

func _bike_update(delta):
    match player_controller.state.player_state:
        BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED:
            # Engine stalls during crash
            if !player_controller.state.is_stalled:
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
            if player_controller.state.is_boosting or player_controller.state.isEasyDifficulty():
                _update_auto_shift()

func _bike_reset():
    player_controller.state.current_gear = 1
    player_controller.state.current_rpm = player_controller.bike_resource.idle_rpm
    player_controller.state.is_stalled = false
    player_controller.state.clutch_value = 0.0
    clutch_hold_time = 0.0
#endregion

#region input handlers
func _on_clutch_input(held: bool, just_pressed: bool):
    clutch_held = held
    clutch_just_pressed = just_pressed


func _on_gear_up():
    # Easy mode: auto-shift handles this, ignore manual input
    if player_controller.state.isEasyDifficulty():
        return
    # Medium: no clutch needed, Hard: clutch required
    var can_shift = player_controller.state.isMediumDifficulty() or player_controller.state.clutch_value > gear_shift_threshold
    if can_shift:
        if player_controller.state.current_gear < player_controller.bike_resource.num_gears:
            player_controller.state.current_gear += 1
            gear_changed.emit(player_controller.state.current_gear)
    else:
        gear_grind.emit()


func _on_gear_down():
    # Easy mode: auto-shift handles this, ignore manual input
    if player_controller.state.isEasyDifficulty():
        return
    # Medium: no clutch needed, Hard: clutch required
    var can_shift = player_controller.state.isMediumDifficulty() or player_controller.state.clutch_value > gear_shift_threshold
    if can_shift:
        if player_controller.state.current_gear > 1:
            player_controller.state.current_gear -= 1
            gear_changed.emit(player_controller.state.current_gear)
    else:
        gear_grind.emit()
#endregion

func update_clutch(delta: float):
    var br := player_controller.bike_resource
    if clutch_held:
        clutch_hold_time += delta
        if clutch_just_pressed:
            # Tap: instantly add to clutch value
            player_controller.state.clutch_value = minf(player_controller.state.clutch_value + br.clutch_tap_amount, 1.0)
        elif clutch_hold_time >= br.clutch_hold_delay:
            # Held past delay: pull in fully
            player_controller.state.clutch_value = move_toward(player_controller.state.clutch_value, 1.0, br.clutch_engage_speed * delta)
    else:
        clutch_hold_time = 0.0
        # Release: slowly let clutch out
        player_controller.state.clutch_value = move_toward(player_controller.state.clutch_value, 0.0, br.clutch_release_speed * delta)


func get_clutch_engagement() -> float:
    """Returns 0-1 where 0 = clutch pulled in (disengaged), 1 = clutch released (engaged to wheel)"""
    return 1.0 - player_controller.state.clutch_value


func get_max_speed_for_gear() -> float:
    var br := player_controller.bike_resource
    var gear_ratio = br.gear_ratios[player_controller.state.current_gear - 1]
    var lowest_ratio = br.gear_ratios[br.num_gears - 1]
    return br.max_speed * (lowest_ratio / gear_ratio)


func update_rpm(delta: float):
    var br := player_controller.bike_resource

    if player_controller.state.is_stalled:
        player_controller.state.current_rpm = 0.0
        var should_start = false
        # Restart engine with throttle + clutch while stalled
        if player_controller.state.clutch_value > 0.5 and player_controller.bike_input.throttle > 0.3:
            should_start = true
        # Easy mode: auto-start with throttle only (no clutch required)
        if player_controller.state.isEasyDifficulty() and player_controller.bike_input.throttle > 0.1:
            should_start = true

        if should_start:
            player_controller.state.is_stalled = false
            player_controller.state.current_rpm = br.idle_rpm
            engine_started.emit()
        return

    var engagement = get_clutch_engagement()

    # Calculate wheel-driven RPM based on wheel speed
    var gear_max_speed = get_max_speed_for_gear()
    var speed_ratio = player_controller.state.speed / gear_max_speed if gear_max_speed > 0 else 0.0
    var wheel_rpm = speed_ratio * br.max_rpm

    # Throttle-driven RPM (instant - no smoothing, engine revs freely)
    var throttle_rpm = lerpf(br.idle_rpm, br.max_rpm, player_controller.bike_input.throttle)

    # Easy mode: automatic clutch - disengage when stationary/slow to allow revving
    if player_controller.state.isEasyDifficulty() and player_controller.state.speed < 5.0:
        engagement = clamp(player_controller.state.speed / 5.0, 0.0, 1.0)

    # Blend between throttle RPM and wheel RPM based on clutch engagement
    # engagement = 0: clutch in, engine free-revs (fast response)
    # engagement = 1: clutch out, engine locked to wheel (follows wheel speed)
    var target_rpm = lerpf(throttle_rpm, wheel_rpm, engagement)

    # When clutch is fully engaged, RPM follows wheel speed
    if engagement > 0.95:
        if !player_controller.state.isHardDifficulty():
            # Easy/Medium: smooth rev-matching when shifting (RPM blends to new gear's wheel RPM)
            player_controller.state.current_rpm = lerpf(player_controller.state.current_rpm, wheel_rpm, br.rev_match_speed * delta)
        else:
            # Hard: RPM locked directly to wheel speed
            player_controller.state.current_rpm = wheel_rpm
    else:
        # RPM blend speed: fast when free-revving, slower when engaged to wheel
        var blend_speed = lerpf(12.0, br.rpm_blend_speed, engagement)
        player_controller.state.current_rpm = lerpf(player_controller.state.current_rpm, target_rpm, blend_speed * delta)

    # Check for stall when clutch is mostly engaged and RPM too low (skip on easy mode)
    if !player_controller.state.isEasyDifficulty() and engagement > 0.9 and player_controller.state.current_rpm < br.stall_rpm:
        player_controller.state.is_stalled = true
        player_controller.state.current_gear = 1
        engine_stalled.emit()
        return

    # Rev limiter: cut RPM when at redline with throttle (creates oscillation)
    var limiter_point = br.max_rpm - br.redline_threshold
    if player_controller.state.current_rpm >= limiter_point and player_controller.bike_input.throttle > 0.5:
        player_controller.state.current_rpm = limiter_point - br.redline_cut_amount

    player_controller.state.current_rpm = clamp(player_controller.state.current_rpm, br.idle_rpm, br.max_rpm)

func get_rpm_ratio() -> float:
    var br := player_controller.bike_resource
    if br.max_rpm <= br.idle_rpm:
        return 0.0
    return (player_controller.state.current_rpm - br.idle_rpm) / (br.max_rpm - br.idle_rpm)


func _update_auto_shift():
    var rpm_ratio = get_rpm_ratio()
    if rpm_ratio >= auto_shift_up_rpm and player_controller.state.current_gear < player_controller.bike_resource.num_gears:
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
    if player_controller.state.isEasyDifficulty():
        engagement = 1.0
    elif engagement < 0.05:
        return 0.0

    var rpm_ratio = get_rpm_ratio()
    var power_curve = rpm_ratio * (2.0 - rpm_ratio) # Peaks around 75% RPM

    var br := player_controller.bike_resource
    var gear_ratio = br.gear_ratios[player_controller.state.current_gear - 1]
    var base_ratio = br.gear_ratios[br.num_gears - 1]
    var torque_multiplier = gear_ratio / base_ratio

    var effective_throttle = player_controller.bike_tricks.get_boosted_throttle(player_controller.bike_input.throttle)
    return effective_throttle * power_curve * torque_multiplier * engagement


func is_clutch_dump(last_clutch: float) -> bool:
    """Returns true if clutch was just dumped while revving"""
    return last_clutch > 0.7 and player_controller.state.clutch_value < 0.3 and player_controller.bike_input.throttle > 0.5
