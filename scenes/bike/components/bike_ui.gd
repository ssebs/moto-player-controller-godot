class_name BikeUI extends BikeComponent

var toast_timer: float = 0.0
const TOAST_DURATION: float = 1.5

# Trick feed system
const TRICK_FEED_DURATION: float = 2.0
const TRICK_FEED_MAX_ITEMS: int = 5
var _trick_feed: Array = []  # Array of {name: String, score: int, timer: float}

func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller

    # Hide toasts initially
    if player_controller.boost_toast:
        player_controller.boost_toast.visible = false
    if player_controller.respawn_label:
        player_controller.respawn_label.visible = false

    player_controller.bike_input.difficulty_toggled.connect(_on_difficulty_toggled)
    player_controller.bike_crash.crashed.connect(_on_crashed)
    player_controller.bike_tricks.boost_started.connect(_on_boost_started)
    player_controller.bike_tricks.boost_ended.connect(_on_boost_ended)
    player_controller.bike_tricks.boost_earned.connect(show_boost_toast)
    player_controller.bike_tricks.trick_ended.connect(_on_trick_ended)


func _bike_update(delta):
    update_ui(player_controller.state.rpm_ratio)
    _update_toast(delta)
    _update_trick_feed(delta)


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

    # Score display
    if player_controller.score_label:
        player_controller.score_label.text = "Score: %d" % int(player_controller.state.total_score)

    # Current trick display
    if player_controller.trick_label:
        var trick_name = player_controller.bike_tricks.get_current_trick_name()
        if trick_name != "":
            player_controller.trick_label.text = trick_name
            player_controller.trick_label.visible = true
            # Show building score
            var building_score = int(player_controller.state.trick_score)
            if building_score > 0:
                player_controller.trick_label.text += " +%d" % building_score
        else:
            player_controller.trick_label.visible = false

    # Combo display
    if player_controller.combo_label:
        if player_controller.state.combo_count > 0:
            player_controller.combo_label.text = "x%.2f (%d)" % [player_controller.state.combo_multiplier, player_controller.state.combo_count]
            player_controller.combo_label.visible = true
        else:
            player_controller.combo_label.visible = false


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
    # Cycle through difficulties: EASY -> MEDIUM -> HARD -> EASY
    var diff = player_controller.state.difficulty
    if diff == player_controller.state.PlayerDifficulty.EASY:
        player_controller.state.difficulty = player_controller.state.PlayerDifficulty.MEDIUM
    elif diff == player_controller.state.PlayerDifficulty.MEDIUM:
        player_controller.state.difficulty = player_controller.state.PlayerDifficulty.HARD
    else:
        player_controller.state.difficulty = player_controller.state.PlayerDifficulty.EASY
    _update_difficulty_display()


func _update_difficulty_display():
    if !player_controller.difficulty_label:
        return
    match player_controller.state.difficulty:
        player_controller.state.PlayerDifficulty.EASY:
            player_controller.difficulty_label.text = "Easy"
            player_controller.difficulty_label.modulate = Color(0.2, 0.8, 0.2)
        player_controller.state.PlayerDifficulty.MEDIUM:
            player_controller.difficulty_label.text = "Medium"
            player_controller.difficulty_label.modulate = Color(0.8, 0.8, 0.2)
        player_controller.state.PlayerDifficulty.HARD:
            player_controller.difficulty_label.text = "Hard"
            player_controller.difficulty_label.modulate = Color(1.0, 0.3, 0.3)


func _on_crashed(_pitch_direction: float, _lean_direction: float):
    if player_controller.respawn_label:
        player_controller.respawn_label.visible = true


func _on_boost_started():
    show_speed_lines()


func _on_boost_ended():
    hide_speed_lines()


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
    _trick_feed.clear()
    if player_controller.boost_toast:
        player_controller.boost_toast.visible = false
    if player_controller.respawn_label:
        player_controller.respawn_label.visible = false
    if player_controller.trick_feed_label:
        player_controller.trick_feed_label.text = ""


func _on_trick_ended(trick: int, score: float, _duration: float):
    """Add completed trick to the feed."""
    var trick_name = BikeTricks.TRICK_DATA[trick].name
    _trick_feed.push_front({
        "name": trick_name,
        "score": int(score),
        "timer": TRICK_FEED_DURATION
    })
    # Limit feed size
    if _trick_feed.size() > TRICK_FEED_MAX_ITEMS:
        _trick_feed.pop_back()


func _update_trick_feed(delta: float):
    """Update trick feed timers and display."""
    # Update timers and remove expired entries
    var i = _trick_feed.size() - 1
    while i >= 0:
        _trick_feed[i].timer -= delta
        if _trick_feed[i].timer <= 0:
            _trick_feed.remove_at(i)
        i -= 1

    # Update display
    if player_controller.trick_feed_label:
        if _trick_feed.size() > 0:
            var feed_text = ""
            for item in _trick_feed:
                var _alpha = clampf(item.timer / TRICK_FEED_DURATION, 0.3, 1.0)  # TODO: use for fade effect
                feed_text += "%s +%d\n" % [item.name, item.score]
            player_controller.trick_feed_label.text = feed_text.strip_edges()
            player_controller.trick_feed_label.visible = true
        else:
            player_controller.trick_feed_label.visible = false