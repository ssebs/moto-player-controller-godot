class_name BikeComponent extends Node

var player_controller: PlayerController

func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller

func _bike_update(_delta: float):
    pass

func _bike_reset():
    pass
