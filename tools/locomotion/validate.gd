extends SceneTree
func _initialize(): call_deferred("validate")
func validate():
 var model = load("res://assets/models/kengeki/kengeki_character_animated.glb").instantiate()
 root.add_child(model)
 var skeleton: Skeleton3D = model.get_node("Kengeki_Rig/Skeleton3D")
 var failures = 0
 if skeleton.get_bone_count()!=101: failures+=1
 for name in ["walk","run","jump"]:
  var clip: Animation = load("res://assets/animations/locomotion/"+name+".res")
  for track in clip.get_track_count():
   var path = clip.track_get_path(track)
   if path.get_subname_count()==0 or skeleton.find_bone(path.get_subname(0))<0: failures+=1
   for key in clip.track_get_key_count(track):
    var value = clip.track_get_key_value(track,key)
    if value is Vector3 and not value.is_finite(): failures+=1
    if value is Quaternion and (not value.is_finite() or absf(value.length()-1.0)>0.001): failures+=1
  print("VALIDATED ",name," tracks=",clip.get_track_count())
 print("RESOURCE_VALIDATION failures=",failures," bones=",skeleton.get_bone_count())
 model.queue_free()
 quit(failures)
