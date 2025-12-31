# NOTE: this is just a reference.
class_name BikeComponentRef extends Node

# Shared state
var state: BikeState

func _bike_setup(bike_state: BikeState, _bike_input: BikeInput):
    state = bike_state

func _bike_update(_delta):
    pass

func _bike_reset():
    pass
