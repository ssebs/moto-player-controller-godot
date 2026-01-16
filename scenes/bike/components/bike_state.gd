class_name BikeState extends Resource

# Difficulty levels
enum PlayerDifficulty {
	EASY, # Automatic transmission
	MEDIUM, # Semi-auto (no clutch needed for shifts)
	HARD # Full manual (clutch required)
}

#region Player state machine
signal state_changed(old_state: PlayerState, new_state: PlayerState)
var player_state: PlayerState = PlayerState.IDLE

enum PlayerState {
	IDLE, # Stationary, no throttle
	RIDING, # On ground, moving
	AIRBORNE, # In air, no trick
	TRICK_AIR, # In air, doing a trick
	TRICK_GROUND, # Wheelie/stoppie/fishtail
	CRASHING, # Crash in progress
	CRASHED # Waiting for respawn
}

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
	# print("StateChange: %s => %s" % [old, new_state])
	state_changed.emit(old, new_state)
	return true

func get_player_state_as_str(ps: PlayerState) -> String:
	match ps:
		PlayerState.IDLE:
			return "IDLE"
		PlayerState.RIDING:
			return "RIDING"
		PlayerState.AIRBORNE:
			return "AIRBORNE"
		PlayerState.TRICK_AIR:
			return "TRICK_AIR"
		PlayerState.TRICK_GROUND:
			return "TRICK_GROUND"
		PlayerState.CRASHING:
			return "CRASHING"
		PlayerState.CRASHED:
			return "CRASHED"
		_:
			return "N/A"

#endregion

func isEasyDifficulty() -> bool:
	return difficulty == PlayerDifficulty.EASY
func isMediumDifficulty() -> bool:
	return difficulty == PlayerDifficulty.MEDIUM
func isHardDifficulty() -> bool:
	return difficulty == PlayerDifficulty.HARD


# Physics state
var speed: float = 0.0
var lean_angle: float = 0.0 # in radians

# Gearing state
var current_gear: int = 1
var current_rpm: float = 1000.0
var clutch_value: float = 0.0
var is_stalled: bool = false
var rpm_ratio: float = 0.0 # Cached per frame by BikeGearing

# Tricks state
var pitch_angle: float = 0.0 # in radians
var fishtail_angle: float = 0.0 # 0 = not fishtailing

# Trick scoring state
var active_trick: int = 0 # BikeTricks.Trick enum (0 = NONE)
var trick_start_time: float = 0.0
var trick_score: float = 0.0
var boost_trick_score: float = 0.0 # Separate score for boost modifier
var total_score: float = 0.0
var combo_multiplier: float = 1.0
var combo_count: int = 0

# Boost state
var is_boosting: bool = false
var boost_count: int = 2

# Grip/Crash state
var grip_usage: float = 0.0 # 0-1, how much grip is being consumed

# Difficulty
var difficulty: PlayerDifficulty = PlayerDifficulty.EASY

# Ground alignment
var ground_pitch: float = 0.0
