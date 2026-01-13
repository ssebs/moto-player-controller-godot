class_name BikeUI extends BikeComponent

var toast_timer: float = 0.0
const TOAST_DURATION: float = 1.5

# Trick feed system
const TRICK_FEED_DURATION: float = 2.0
const TRICK_FEED_MAX_ITEMS: int = 5
var _trick_feed: Array = [] # Array of {name: String, score: int, timer: float}

#region BikeComponent lifecycle
func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller
    player_controller.state.state_changed.connect(_on_player_state_changed)

    # Hide toasts initially
    if player_controller.boost_toast:
        player_controller.boost_toast.visible = false
    if player_controller.respawn_label:
        player_controller.respawn_label.visible = false

    player_controller.bike_input.difficulty_toggled.connect(_on_difficulty_toggled)
    player_controller.bike_crash.crashed.connect(_on_crashed)
    player_controller.bike_tricks.trick_ended.connect(_on_trick_ended)
    player_controller.bike_tricks.boost_started.connect(_on_boost_started)
    player_controller.bike_tricks.boost_ended.connect(_on_boost_ended)
    player_controller.bike_tricks.boost_earned.connect(_on_boost_earned)

func _bike_update(delta):
    _update_labels()
    _update_bars()
    _update_difficulty_display()
    _update_toast(delta)
    _update_trick_feed(delta)
    _update_vibration()

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
#endregion

#region signal handlers
# TODO: refactor, this is the only thing that uses signals from bike_input
func _on_difficulty_toggled():
    # Cycle through difficulties: EASY -> MEDIUM -> HARD -> EASY
    if player_controller.state.isEasyDifficulty():
        player_controller.state.difficulty = player_controller.state.PlayerDifficulty.MEDIUM
    elif player_controller.state.isMediumDifficulty():
        player_controller.state.difficulty = player_controller.state.PlayerDifficulty.HARD
    else:
        player_controller.state.difficulty = player_controller.state.PlayerDifficulty.EASY
    _update_difficulty_display()

func _on_crashed(_pitch_direction: float, _lean_direction: float):
    if player_controller.respawn_label:
        player_controller.respawn_label.visible = true

## Add completed trick to the feed.
func _on_trick_ended(trick: int, score: float, _duration: float):
    _trick_feed.push_front({
        "name": BikeTricks.TRICK_DATA[trick].name,
        "score": int(score),
        "diff_mult": BikeTricks.DIFFICULTY_MULT.get(player_controller.state.difficulty, 1.0),
        "timer": TRICK_FEED_DURATION
    })
    # Limit feed size
    if _trick_feed.size() > TRICK_FEED_MAX_ITEMS:
        _trick_feed.pop_back()

func _on_boost_started():
    show_speed_lines()
    # Show boost notification with difficulty multiplier
    if player_controller.boost_toast:
        var diff_mult = BikeTricks.DIFFICULTY_MULT.get(player_controller.state.difficulty, 1.0)
        player_controller.boost_toast.text = "BOOST! (x%.1f)" % diff_mult
        player_controller.boost_toast.visible = true
        toast_timer = TOAST_DURATION

func _on_boost_ended():
    hide_speed_lines()

func _on_boost_earned():
    if player_controller.boost_toast:
        player_controller.boost_toast.visible = true
        toast_timer = TOAST_DURATION

#endregion

#region update funcs
func _update_labels():
    # Gear label
    if player_controller.state.is_stalled:
        player_controller.gear_label.text = "STALLED\nGear: %d" % player_controller.state.current_gear
    else:
        player_controller.gear_label.text = "Gear: %d" % player_controller.state.current_gear

    # Speed label
    player_controller.speed_label.text = "Speed: %d" % int(player_controller.state.speed)

    # Boost label
    if player_controller.boost_label:
        player_controller.boost_label.text = "Boost: %d" % player_controller.state.boost_count

    # Score label
    if player_controller.score_label:
        player_controller.score_label.text = "Score: %d" % int(player_controller.state.total_score)

    # Current trick label
    if player_controller.bike_tricks.get_current_trick_name() != "":
        player_controller.trick_label.text = player_controller.bike_tricks.get_current_trick_name()
        player_controller.trick_label.visible = true
        # Show building score
        var building_score = int(player_controller.state.trick_score)
        if building_score > 0:
            player_controller.trick_label.text += " +%d" % building_score
    else:
        player_controller.trick_label.visible = false

    # Combo label
    if player_controller.combo_label:
        if player_controller.state.combo_count > 0:
            player_controller.combo_label.text = "x%.2f (%d)" % [player_controller.state.combo_multiplier, player_controller.state.combo_count]
            player_controller.combo_label.visible = true
        else:
            player_controller.combo_label.visible = false

func _update_bars():
    # Set throttle bar
    player_controller.throttle_bar.value = player_controller.bike_input.throttle
    if player_controller.state.rpm_ratio > 0.9:
        player_controller.throttle_bar.modulate = Color(1.0, 0.2, 0.2) # Red at redline
    else:
        player_controller.throttle_bar.modulate = Color(0.2, 0.8, 0.2) # Green

    # Set RPM bar
    player_controller.rpm_bar.value = player_controller.state.rpm_ratio
    if player_controller.state.rpm_ratio > 0.9:
        player_controller.rpm_bar.modulate = Color(1.0, 0.2, 0.2) # Red at redline
    elif player_controller.state.rpm_ratio > 0.7:
        player_controller.rpm_bar.modulate = Color(1.0, 0.8, 0.2) # Yellow/orange approaching redline
    else:
        player_controller.rpm_bar.modulate = Color(0.2, 0.6, 1.0) # Blue for normal range

    # Set brake danger bar
    player_controller.brake_danger_bar.value = player_controller.bike_input.front_brake
    if player_controller.state.grip_usage > 0.1:
        var danger_color = Color(1.0, 1.0 - player_controller.state.grip_usage, 0.0)
        player_controller.brake_danger_bar.modulate = danger_color
    else:
        player_controller.brake_danger_bar.modulate = Color(0.3, 0.5, 0.9)

    # Set clutch bar
    if player_controller.clutch_bar:
        player_controller.clutch_bar.value = player_controller.state.clutch_value
        player_controller.clutch_bar.modulate = Color(0.8, 0.6, 0.2) # Orange/yellow

# TODO: refactor this, toast_timer is only used for boost_toast.
func _update_toast(delta):
    if toast_timer > 0:
        toast_timer -= delta
        if toast_timer <= 0 and player_controller.boost_toast:
            player_controller.boost_toast.visible = false

## Apply vibration from tricks
# TODO: move to bike_tricks
func _update_vibration():
    var weak_total = 0.0
    var strong_total = 0.0

    # Get vibration from components
    if player_controller.bike_tricks:
        var grip_vibe = player_controller.bike_tricks.get_grip_vibration()
        weak_total += grip_vibe.x
        strong_total += grip_vibe.y

        var fishtail_vibe = player_controller.bike_tricks.get_fishtail_vibration()
        weak_total += fishtail_vibe.x
        strong_total += fishtail_vibe.y

    # Apply vibration through input component
    player_controller.bike_input.add_vibration(weak_total, strong_total)

func _update_difficulty_display():
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

## Update trick feed timers and display.
func _update_trick_feed(delta: float):
    # Update timers and remove expired entries
    var i = _trick_feed.size() - 1
    while i >= 0:
        _trick_feed[i].timer -= delta
        if _trick_feed[i].timer <= 0:
            _trick_feed.remove_at(i)
        i -= 1

    # Update display
    if _trick_feed.size() > 0:
        var feed_text = ""
        for item in _trick_feed:
            var _alpha = clampf(item.timer / TRICK_FEED_DURATION, 0.3, 1.0)
            var mult_str = "x%.1f" % item.diff_mult if item.diff_mult != 1.0 else ""
            if mult_str != "":
                feed_text += "%s +%d (%s)\n" % [item.name, item.score, mult_str]
            else:
                feed_text += "%s +%d\n" % [item.name, item.score]
        player_controller.trick_feed_label.text = feed_text.strip_edges()
        player_controller.trick_feed_label.visible = true
    else:
        player_controller.trick_feed_label.visible = false

#endregion

func show_speed_lines():
    if player_controller.speed_lines_effect:
        player_controller.speed_lines_effect.visible = true

func hide_speed_lines():
    if player_controller.speed_lines_effect:
        player_controller.speed_lines_effect.visible = false
