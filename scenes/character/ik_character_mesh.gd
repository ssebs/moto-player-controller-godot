@tool
class_name IKCharacterMesh extends Node3D

@export var skel: Skeleton3D
@export var root_bone_name: String = "mixamorig6_Hips"

# Target markers
@export var head_target: Marker3D
@export var left_arm_target: Marker3D
@export var right_arm_target: Marker3D
@export var butt_target: Marker3D
@export var left_leg_target: Marker3D
@export var right_leg_target: Marker3D

# IK magnet positions
@export var left_arm_magnet: Vector3 = Vector3(0, 0, 0)
@export var right_arm_magnet: Vector3 = Vector3(0, 0, 0)
@export var left_leg_magnet: Vector3 = Vector3(0.1, 0, 1)
@export var right_leg_magnet: Vector3 = Vector3(-0.1, 0, 1)

# IK nodes
@onready var head_ik: SkeletonIK3D = %HeadIK
@onready var left_arm_ik: SkeletonIK3D = %LeftArmIK
@onready var right_arm_ik: SkeletonIK3D = %RightArmIK
# note: butt doesn't use IK
@onready var left_leg_ik: SkeletonIK3D = %LeftLegIK
@onready var right_leg_ik: SkeletonIK3D = %RightLegIK

func _ready():
    _update_ik_magnets()

func _update_ik_magnets():
    if left_arm_ik:
        left_arm_ik.magnet = left_arm_magnet
    if right_arm_ik:
        right_arm_ik.magnet = right_arm_magnet
    if left_leg_ik:
        left_leg_ik.magnet = left_leg_magnet
    if right_leg_ik:
        right_leg_ik.magnet = right_leg_magnet

func _physics_process(_delta):
    move_butt()

# Move skel's root bone to butt_target
func move_butt():
    var bone_idx = skel.find_bone(root_bone_name)
    if bone_idx == -1:
        printerr("can't find bone %s" % root_bone_name)
        return

    var offset = butt_target.position
    var rot = Quaternion.from_euler(butt_target.rotation)
    skel.set_bone_pose_position(bone_idx, offset)
    skel.set_bone_pose_rotation(bone_idx, rot)
