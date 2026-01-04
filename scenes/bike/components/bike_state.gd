class_name BikeState extends Resource

# Player state machine
enum PlayerState {
	IDLE, # Stationary, no throttle
	RIDING, # On ground, moving
	AIRBORNE, # In air, no trick
	TRICK_AIR, # In air, doing a trick
	TRICK_GROUND, # Wheelie/stoppie/fishtail
	CRASHING, # Crash in progress
	CRASHED # Waiting for respawn
}

signal state_changed(old_state: PlayerState, new_state: PlayerState)

var player_state: PlayerState = PlayerState.IDLE

const VALID_TRANSITIONS: Dictionary = {
	PlayerState.IDLE: [PlayerState.RIDING, PlayerState.AIRBORNE, PlayerState.CRASHING],
	PlayerState.RIDING: [PlayerState.IDLE, PlayerState.AIRBORNE, PlayerState.TRICK_GROUND, PlayerState.CRASHING],
	PlayerState.AIRBORNE: [PlayerState.RIDING, PlayerState.TRICK_AIR, PlayerState.TRICK_GROUND, PlayerState.CRASHING],
	PlayerState.TRICK_AIR: [PlayerState.AIRBORNE, PlayerState.RIDING, PlayerState.TRICK_GROUND, PlayerState.CRASHING],
	PlayerState.TRICK_GROUND: [PlayerState.RIDING, PlayerState.AIRBORNE, PlayerState.CRASHING],
	PlayerState.CRASHING: [PlayerState.CRASHED],
	PlayerState.CRASHED: [PlayerState.IDLE]
}


func request_state_change(new_state: PlayerState) -> bool:
	if new_state == player_state:
		return false
	if new_state not in VALID_TRANSITIONS.get(player_state, []):
		return false
	var old = player_state
	player_state = new_state
	print("StateChange: %s => %s" % [old, new_state])
	state_changed.emit(old, new_state)
	return true


# Physics state
var speed: float = 0.0
var steering_angle: float = 0.0
var lean_angle: float = 0.0
var fall_angle: float = 0.0 # Bike falling over due to lack of gyroscopic stability

# Gearing state
var current_gear: int = 1
var current_rpm: float = 1000.0
var clutch_value: float = 0.0
var is_stalled: bool = false
var rpm_ratio: float = 0.0  # Cached per frame by BikeGearing

# Tricks state
var pitch_angle: float = 0.0
var fishtail_angle: float = 0.0

# Boost state
var is_boosting: bool = false
var boost_count: int = 2

# Crash state
var brake_danger_level: float = 0.0
var brake_grab_level: float = 0.0

# Difficulty
var is_easy_mode: bool = true

# Ground alignment
var ground_pitch: float = 0.0
