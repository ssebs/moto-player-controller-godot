class_name BikeInput extends BikeComponent

signal throttle_changed(value: float)
signal front_brake_changed(value: float)
signal rear_brake_changed(value: float)
signal steer_changed(value: float) # lean left/right
signal lean_changed(value: float) # lean back/fwd
signal clutch_held_changed(held: bool, just_pressed: bool)
signal gear_up_pressed
signal gear_down_pressed
signal difficulty_toggled
signal trick_changed(value: float)


# Vibration settings
@export var vibration_duration: float = 0.15

# Input state (with change detection)
var throttle: float = 0.0:
	set(value):
		if throttle != value:
			throttle = value
			throttle_changed.emit(value)

var front_brake: float = 0.0:
	set(value):
		if front_brake != value:
			front_brake = value
			front_brake_changed.emit(value)

var rear_brake: float = 0.0:
	set(value):
		if rear_brake != value:
			rear_brake = value
			rear_brake_changed.emit(value)

var steer: float = 0.0:
	set(value):
		if steer != value:
			steer = value
			steer_changed.emit(value)

var lean: float = 0.0:
	set(value):
		if lean != value:
			lean = value
			lean_changed.emit(value)

var trick: bool = false:
	set(value):
		if trick != value:
			trick = value
			trick_changed.emit(value)

func _bike_setup(p_controller: PlayerController):
	player_controller = p_controller
	# TODO: MP check for authority

func _bike_update(_delta):
	_update_input()


func _update_input():
	throttle = Input.get_action_strength("throttle_pct")
	front_brake = Input.get_action_strength("brake_front_pct")
	rear_brake = Input.get_action_strength("brake_rear")

	steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	lean = Input.get_action_strength("lean_back") - Input.get_action_strength("lean_forward")

	clutch_held_changed.emit(
		Input.is_action_pressed("clutch"),
		Input.is_action_just_pressed("clutch")
	)

	trick = Input.is_action_pressed("trick")

	if Input.is_action_just_pressed("gear_up"):
		gear_up_pressed.emit()
	if Input.is_action_just_pressed("gear_down"):
		gear_down_pressed.emit()

	if Input.is_action_just_pressed("change_difficulty"):
		difficulty_toggled.emit()


func add_vibration(weak: float, strong: float):
	"""Add vibration intensity from external sources. Call this each frame vibration is needed."""
	if weak > 0.01 or strong > 0.01:
		Input.start_joy_vibration(0, clamp(weak, 0.0, 1.0), clamp(strong, 0.0, 1.0), vibration_duration)
	else:
		stop_vibration()

func stop_vibration():
	Input.stop_joy_vibration(0)


func has_input() -> bool:
	"""Returns true if any significant input is being applied"""
	return throttle > 0.1 or front_brake > 0.1 or rear_brake > 0.1


func _bike_reset():
	stop_vibration()
