extends SceneTree
## Reproducible, animation-only bake. Original GLB is read, never written.
const OUT = "res://assets/animations/locomotion/"
var sk: Skeleton3D
var ap: AnimationPlayer
func _initialize(): call_deferred("bake")
func set_global_bone(id: int, pose: Transform3D):
 var parent = sk.get_bone_parent(id)
 var local = sk.get_bone_global_pose(parent).affine_inverse() * pose if parent >= 0 else pose
 sk.set_bone_pose_position(id,local.origin)
 sk.set_bone_pose_rotation(id,local.basis.get_rotation_quaternion())
 sk.force_update_all_bone_transforms()
func solve_leg(side: String, target: Transform3D):
 var thigh = sk.find_bone("CC_Base_%s_Thigh" % side)
 var calf = sk.find_bone("CC_Base_%s_Calf" % side)
 var foot = sk.find_bone("CC_Base_%s_Foot" % side)
 var a = sk.get_bone_global_pose(thigh).origin
 var b = sk.get_bone_global_pose(calf).origin
 var c = sk.get_bone_global_pose(foot).origin
 var l1 = a.distance_to(b)
 var l2 = b.distance_to(c)
 var dir = (target.origin-a).normalized()
 var distance = clampf(a.distance_to(target.origin),absf(l1-l2)+0.001,l1+l2-0.001)
 var pole = (b-a)-dir*(b-a).dot(dir)
 if pole.length()<0.001: pole=Vector3.FORWARD-dir*Vector3.FORWARD.dot(dir)
 pole= pole.normalized()
 var along = (l1*l1-l2*l2+distance*distance)/(2*distance)
 var knee = a+dir*along+pole*sqrt(maxf(0,l1*l1-along*along))
 var pose = sk.get_bone_global_pose(thigh)
 pose.basis = Basis(Quaternion((b-a).normalized(),(knee-a).normalized())) * pose.basis
 set_global_bone(thigh,pose)
 b = sk.get_bone_global_pose(calf).origin
 c = sk.get_bone_global_pose(foot).origin
 pose = sk.get_bone_global_pose(calf)
 pose.basis = Basis(Quaternion((c-b).normalized(),(target.origin-b).normalized())) * pose.basis
 set_global_bone(calf,pose)
 pose = sk.get_bone_global_pose(foot)
 pose.basis = target.basis
 set_global_bone(foot,pose)
func bake():
 DirAccess.make_dir_recursive_absolute(OUT)
 var model = load("res://assets/models/kengeki/kengeki_character_animated.glb").instantiate()
 root.add_child(model)
 sk = model.get_node("Kengeki_Rig/Skeleton3D")
 ap = model.find_children("*","AnimationPlayer",true,false)[0]
 var hip = sk.find_bone("CC_Base_Hip")
 var root_id = sk.find_bone("RL_BoneRoot")
 for clip_name in ["Walk","Run","Jump"]:
  var source = ap.get_animation(clip_name)
  var result: Animation = source.duplicate(true)
  var changed = ["CC_Base_Hip","CC_Base_L_Thigh","CC_Base_L_Calf","CC_Base_L_Foot","CC_Base_R_Thigh","CC_Base_R_Calf","CC_Base_R_Foot"]
  if clip_name == "Run": changed.append("CC_Base_Spine01")
  var tracks = {}
  for bone in changed:
   for type in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D]:
    var path = NodePath("Kengeki_Rig/Skeleton3D:"+bone)
    var old = result.find_track(path,type)
    if old>=0: result.remove_track(old)
    var tr = result.add_track(type)
    result.track_set_path(tr,path)
  # Resolve indices only after removals are complete.
  for bone in changed:
   tracks[bone] = [result.find_track(NodePath("Kengeki_Rig/Skeleton3D:"+bone),Animation.TYPE_POSITION_3D),result.find_track(NodePath("Kengeki_Rig/Skeleton3D:"+bone),Animation.TYPE_ROTATION_3D)]
  ap.play(clip_name)
  ap.seek(source.length,true)
  sk.force_update_all_bone_transforms()
  var travel = sk.get_bone_global_pose(root_id).origin
  var steps = int(ceil(source.length*60))
  for f in range(steps+1):
   var t = source.length * f / steps
   # Reset every pose before sampling, because constant tracks can be optimized away.
   sk.reset_bone_poses()
   ap.seek(t,true)
   sk.force_update_all_bone_transforms()
   var feet = [sk.get_bone_global_pose(sk.find_bone("CC_Base_L_Foot")),sk.get_bone_global_pose(sk.find_bone("CC_Base_R_Foot"))]
   var pose = sk.get_bone_global_pose(hip)
   if clip_name != "Jump":
    var stride = 1.10 if clip_name=="Walk" else 1.0
    var root_pos = sk.get_bone_global_pose(root_id).origin
    var linear = travel*t/source.length
    # Keep contact positions in world space when the controller replaces root travel
    # with constant speed. Restore the source's lateral weight transfer as well.
    pose.origin.z = stride*pose.origin.z + root_pos.z - stride*linear.z
    pose.origin.x += root_pos.x
    if clip_name == "Run": pose.origin.y += 0.025
    for i in 2:
     feet[i].origin.z = stride*feet[i].origin.z + root_pos.z - stride*linear.z
     feet[i].origin.x += root_pos.x + (0.015 if i==0 else -0.015)
   else:
    # Soften the over-deep landing squat, keeping the feet in place with two-bone IK.
    var landing = clampf((t-1.396)/(2.167-1.396),0,1)
    pose.origin.y += 0.035*sin(PI*landing)
   set_global_bone(hip,pose)
   solve_leg("L",feet[0])
   solve_leg("R",feet[1])
   if clip_name == "Run":
    var spine = sk.find_bone("CC_Base_Spine01")
    var torso = sk.get_bone_global_pose(spine)
    torso.basis = Basis(Vector3.RIGHT,deg_to_rad(-30.0))*torso.basis
    set_global_bone(spine,torso)
   for bone in changed:
    var id = sk.find_bone(bone)
    result.position_track_insert_key(tracks[bone][0],t,sk.get_bone_pose_position(id))
    result.rotation_track_insert_key(tracks[bone][1],t,sk.get_bone_pose_rotation(id))
  result.loop_mode = Animation.LOOP_NONE if clip_name=="Jump" else Animation.LOOP_LINEAR
  if clip_name!="Jump":
   for bone in changed:
    for tr in tracks[bone]:
     result.track_set_key_value(tr,result.track_get_key_count(tr)-1,result.track_get_key_value(tr,0))
  var err = ResourceSaver.save(result,OUT+clip_name.to_lower()+".res")
  print("BAKED ",clip_name," ",err," tracks=",result.get_track_count())
 model.queue_free()
 quit()
