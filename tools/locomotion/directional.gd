extends "res://tools/locomotion/preview.gd"
var target: Enemy
func _ready():
 super._ready()
 target = preload("res://scenes/characters/enemy.tscn").instantiate()
 target.position = Vector3(0,0,-15)
 add_child(target)
 target.ai.enabled = false
 player.lock_range = 100.0
 player.set_lock_target(target)
func _physics_process(_dt):
 if frame >= 300: return
 frame += 1
 if frame==30: Input.action_press("move_back")
 if frame==180:
  Input.action_release("move_back")
  Input.action_press("move_right")
 if frame==270: Input.action_release("move_right")
 var center = Vector3(player.position.x,1.0,player.position.z)
 camera.position = center + Vector3(5.5,1.0,2.5)
 camera.look_at(center)
 label.text = out.to_upper()+" | "+("BACKPEDAL" if frame<180 else "STRAFE: FORWARD-CLIP LIMITATION")
 if frame%3==0 and DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png("res://build/locomotion/%s/%04d.png" % [out,frame/3])
 if frame==150:
  print("BACKPEDAL direction=",player.visual._gait_direction," local_velocity=",player.visual._local_velocity)
 if frame>=300:
  var file = FileAccess.open("res://build/locomotion/"+out+"_samples.json",FileAccess.WRITE)
  file.store_string(JSON.stringify(samples))
  print("DIRECTIONAL_COMPLETE")
  get_tree().quit()
