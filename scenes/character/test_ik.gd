@tool
extends Node3D

@export var butt_position: Marker3D
@export var skel: Skeleton3D

func _ready():
    pass

func _physics_process(_delta):
    move_butt()

# Move skel's root bone to butt_position
func move_butt(bone_name: String = "mixamorig6_Hips"):
    var bone_idx = skel.find_bone(bone_name)
    if bone_idx == -1:
        printerr("can't find bone %s" % bone_name)
        return

    var offset = butt_position.position
    skel.set_bone_pose_position(bone_idx, offset)
