class_name BikeUI extends Node

# Player controller reference
var player_controller: PlayerController

var toast_timer: float = 0.0
const TOAST_DURATION: float = 1.5

func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller

    # Hide toast initially
    if player_controller.boost_toast:
        player_controller.boost_toast.visible = false

    player_controller.bike_input.difficulty_toggled.connect(_on_difficulty_toggled)


func _bike_update(delta):
    update_ui(player_controller.state.rpm_ratio)
    _update_toast(delta)


func update_ui(rpm_ratio: float):
    _update_labels()
    _update_bars(rpm_ratio)
    _update_vibration()
    _update_difficulty_display()


func _update_labels():
    if !player_controller.gear_label or !player_controller.speed_label:
        return

    if player_controller.state.is_stalled:
        player_controller.gear_label.text = "STALLED\nGear: %d" % player_controller.state.current_gear
    else:
        player_controller.gear_label.text = "Gear: %d" % player_controller.state.current_gear

    player_controller.speed_label.text = "Speed: %d" % int(player_controller.state.speed)

    if player_controller.boost_label:
        player_controller.boost_label.text = "Boost: %d" % player_controller.state.boost_count


func _update_bars(rpm_ratio: float):
    if !player_controller.throttle_bar or !player_controller.brake_danger_bar:
        return

    player_controller.throttle_bar.value = player_controller.bike_input.throttle

    if rpm_ratio > 0.9:
        player_controller.throttle_bar.modulate = Color(1.0, 0.2, 0.2) # Red at redline
    else:
        player_controller.throttle_bar.modulate = Color(0.2, 0.8, 0.2) # Green

    # RPM gauge
    if player_controller.rpm_bar:
        player_controller.rpm_bar.value = rpm_ratio
        if rpm_ratio > 0.9:
            player_controller.rpm_bar.modulate = Color(1.0, 0.2, 0.2) # Red at redline
        elif rpm_ratio > 0.7:
            player_controller.rpm_bar.modulate = Color(1.0, 0.8, 0.2) # Yellow/orange approaching redline
        else:
            player_controller.rpm_bar.modulate = Color(0.2, 0.6, 1.0) # Blue for normal range

    player_controller.brake_danger_bar.value = player_controller.bike_input.front_brake

    if player_controller.state.brake_danger_level > 0.1:
        var danger_color = Color(1.0, 1.0 - player_controller.state.brake_danger_level, 0.0)
        player_controller.brake_danger_bar.modulate = danger_color
    else:
        player_controller.brake_danger_bar.modulate = Color(0.3, 0.5, 0.9)

    if player_controller.clutch_bar:
        player_controller.clutch_bar.value = player_controller.state.clutch_value
        player_controller.clutch_bar.modulate = Color(0.8, 0.6, 0.2) # Orange/yellow


# TODO: move this
func _update_vibration():
    if !player_controller.bike_input:
        return

    var weak_total = 0.0
    var strong_total = 0.0

    # Get vibration from components
    if player_controller.bike_crash:
        var brake_vibe = player_controller.bike_crash.get_brake_vibration()
        weak_total += brake_vibe.x
        strong_total += brake_vibe.y

    if player_controller.bike_tricks:
        var fishtail_vibe = player_controller.bike_tricks.get_fishtail_vibration()
        weak_total += fishtail_vibe.x
        strong_total += fishtail_vibe.y

    # Apply vibration through input component
    player_controller.bike_input.add_vibration(weak_total, strong_total)


# TODO: refactor, this is the only thing that uses signals from bike_input
func _on_difficulty_toggled():
    player_controller.state.is_easy_mode = !player_controller.state.is_easy_mode
    _update_difficulty_display()


func _update_difficulty_display():
    if !player_controller.difficulty_label:
        return
    if player_controller.state.is_easy_mode:
        player_controller.difficulty_label.text = "Easy"
        player_controller.difficulty_label.modulate = Color(0.2, 0.8, 0.2)
    else:
        player_controller.difficulty_label.text = "Hard"
        player_controller.difficulty_label.modulate = Color(1.0, 0.3, 0.3)


func show_speed_lines():
    if player_controller.speed_lines_effect:
        player_controller.speed_lines_effect.visible = true


func hide_speed_lines():
    if player_controller.speed_lines_effect:
        player_controller.speed_lines_effect.visible = false


func show_boost_toast():
    if player_controller.boost_toast:
        player_controller.boost_toast.visible = true
        toast_timer = TOAST_DURATION


func _update_toast(delta):
    if toast_timer > 0:
        toast_timer -= delta
        if toast_timer <= 0 and player_controller.boost_toast:
            player_controller.boost_toast.visible = false


func _bike_reset():
    hide_speed_lines()
    toast_timer = 0.0
    if player_controller.boost_toast:
        player_controller.boost_toast.visible = false