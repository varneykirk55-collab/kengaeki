extends SceneTree
func _initialize(): call_deferred("sample")
func sample():
 var model = load("res://assets/models/kengeki/kengeki_character_animated.glb").instantiate()
 root.add_child(model)
 var sk: Skeleton3D = model.get_node("Kengeki_Rig/Skeleton3D")
 var ap: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
 var data = {}
 for name in ["Walk","Run","Jump"]:
  var clip = ap.get_animation(name)
  ap.play(name)
  var rows = []
  for f in range(int(clip.length * 60)+1):
   var t = minf(f/60.0,clip.length)
   ap.seek(t,true)
   sk.force_update_all_bone_transforms()
   var row = {"t":t}
   for bone in ["RL_BoneRoot","CC_Base_Hip","CC_Base_L_Thigh","CC_Base_L_Calf","CC_Base_L_Foot","CC_Base_L_ToeBase","CC_Base_R_Foot","CC_Base_R_ToeBase","CC_Base_Spine01","CC_Base_NeckTwist01","CC_Base_Head"]:
    var v = sk.get_bone_global_pose(sk.find_bone(bone)).origin
    row[bone] = [v.x,v.y,v.z]
   rows.append(row)
  data[name]=rows
 var file = FileAccess.open("res://build/locomotion/poses.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(data))
 print("SAMPLED")
 model.queue_free()
 quit()
