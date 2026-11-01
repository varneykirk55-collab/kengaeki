extends Node3D
var player: Player
var camera: Camera3D
var label: Label
var frame := 0
var out := "before"
var samples: Array = []
func _ready():
 if not ResourceLoader.exists("res://assets/models/kengeki/kengeki_character_animated.glb"):
  push_error("Preview requires the original private samurai GLB.")
  set_physics_process(false)
  set_process(false)
  get_tree().quit(1)
  return
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
 DirAccess.make_dir_recursive_absolute("res://build/locomotion/" + out)
 var world = WorldEnvironment.new()
 world.environment = Environment.new()
 world.environment.background_mode = Environment.BG_COLOR
 world.environment.background_color = Color(0.14,0.18,0.22)
 world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 world.environment.ambient_light_color = Color.WHITE
 world.environment.ambient_light_energy = 0.65
 add_child(world)
 var light = DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-45,-30,0)
 light.light_energy = 1.8
 add_child(light)
 var floor_body = StaticBody3D.new()
 var col = CollisionShape3D.new()
 var box = BoxShape3D.new()
 box.size = Vector3(100,0.2,100)
 col.shape = box
 col.position.y = -0.1
 floor_body.add_child(col)
 add_child(floor_body)
 for i in range(-50,51):
  var m = MeshInstance3D.new()
  var b = BoxMesh.new()
  b.size = Vector3(30,0.01,0.025)
  m.mesh = b
  m.position = Vector3(0,-0.005,i)
  add_child(m)
 player = preload("res://scenes/characters/player.tscn").instantiate()
 player.get_node("Visual").refined_locomotion = out != "before"
 add_child(player)
 camera = Camera3D.new()
 camera.fov = 37
 add_child(camera)
 camera.current = true
 var canvas = CanvasLayer.new()
 add_child(canvas)
 label = Label.new()
 label.position = Vector2(22,18)
 label.add_theme_font_size_override("font_size",22)
 canvas.add_child(label)
 AudioServer.set_bus_mute(0,true)
func _physics_process(_dt):
 if frame >= 780: return
 frame += 1
 player.stamina.restore_full()
 if frame == 60: Input.action_press("move_forward")
 if frame == 210: Input.action_press("sprint")
 if frame == 330: Input.action_release("sprint")
 if frame == 420: Input.action_release("move_forward")
 if frame == 480 or frame == 615:
  var e = InputEventAction.new()
  e.action = "jump"
  e.pressed = true
  player._unhandled_input(e)
 if frame == 570: Input.action_press("move_forward")
 if frame == 720: Input.action_release("move_forward")
 var section = "IDLE"
 if frame >= 60 and frame < 210: section = "WALK | 4.6 m/s"
 elif frame < 330 and frame >= 210: section = "RUN | 7.4 m/s"
 elif frame >= 330 and frame < 420: section = "RUN > WALK"
 elif frame >= 480 and frame < 570: section = "STANDING JUMP / LAND"
 elif frame >= 570 and frame < 720: section = "MOVING JUMP / LAND"
 label.text = out.to_upper() + "  |  " + section + "\nGodot 4.3 | same player physics | side view"
 var center = Vector3(player.position.x,1.0,player.position.z)
 camera.position = center + Vector3(5.5,1.0,2.5)
 camera.look_at(center)
 if frame % 3 == 0 and DisplayServer.get_name() != "headless":
  await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png("res://build/locomotion/%s/%04d.png" % [out,frame/3])
 if frame >= 780:
  var file = FileAccess.open("res://build/locomotion/"+out+"_samples.json",FileAccess.WRITE)
  file.store_string(JSON.stringify(samples))
  print("PREVIEW_COMPLETE ",out)
  get_tree().quit()

func _process(_dt):
 if not is_instance_valid(player): return
 var visual = player.visual as KengekiCharacterVisual
 if visual.skeleton == null: return
 var row = {"frame":frame,"speed":Vector2(player.velocity.x,player.velocity.z).length(),"state":player.state}
 for bone in ["CC_Base_L_Foot","CC_Base_R_Foot","CC_Base_L_ToeBase","CC_Base_R_ToeBase"]:
  var pos = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone(bone)).origin
  row[bone] = [pos.x,pos.y,pos.z]
 samples.append(row)
