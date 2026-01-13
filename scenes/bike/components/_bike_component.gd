class_name BikeComponent extends Node3D

var player_controller: PlayerController

#region BikeComponent lifecycle
func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller
    player_controller.state.state_changed.connect(_on_player_state_changed)

func _bike_update(_delta: float):
    pass

func _bike_reset():
    pass

func _on_player_state_changed(_old_state: BikeState.PlayerState, _new_state: BikeState.PlayerState):
    pass

#endregion
