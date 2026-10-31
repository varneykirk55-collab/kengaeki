## Reference audit (read-only): every resource reference in the repo resolves, and every texture /
## model / material under environment/courtyard/ is reachable from some scene.
## Run: godot --headless --path . -s res://tools/courtyard/ref_check.gd
extends SceneTree

var _seen := {}
# Kept on purpose although no scene loads them (documented; not counted as a failure).
# Empty: the unused 25k lantern was removed (Oct 30, 2026, DEVIATIONS.md #14).
const KNOWN_UNUSED := {}
var _broken: Array = []

func _files(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		out.append(dir.path_join(f))
	for s in d.get_directories():
		if s.begins_with("."):
			continue
		_files(dir.path_join(s), out)

func _walk(path: String, from: String) -> void:
	if _seen.has(path):
		return
	_seen[path] = true
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		_broken.append("%s (referenced by %s)" % [path, from])
		return
	for dep in ResourceLoader.get_dependencies(path):
		var p: String = dep.get_slice("::", 2) if dep.contains("::") else dep
		if p.begins_with("uid://"):
			var id := ResourceUID.text_to_id(p)
			if not ResourceUID.has_id(id):
				_broken.append("%s (referenced by %s)" % [dep, path])
				continue
			p = ResourceUID.get_id_path(id)
		_walk(p, path)

func _initialize() -> void:
	var all: Array = []
	_files("res://", all)
	var roots := 0
	for f in all:
		if f.ends_with(".tscn") or f.ends_with(".tres") or f.ends_with(".gd"):
			if f.begins_with("res://.godot"):
				continue
			roots += 1
			_walk(f, "root")
			# CourtyardProp loads its models from path strings (model_path, model_lod_paths), which
			# are not ext_resources: follow every quoted res:// path in the text as well.
			if f.ends_with(".tscn") or f.ends_with(".tres"):
				var rx := RegEx.create_from_string("\"(res://[^\"]+\\.(?:glb|gltf|png|jpg|tres|tscn))\"")
				for m in rx.search_all(FileAccess.get_file_as_string(f)):
					_walk(m.get_string(1), f)
	var unref: Array = []
	var assets := 0
	for f in all:
		if not f.begins_with("res://environment/courtyard/"):
			continue
		var ext: String = f.get_extension().to_lower()
		if ext in ["png", "jpg", "jpeg", "webp", "glb", "gltf", "tres", "res", "material"]:
			assets += 1
			if not _seen.has(f):
				var known := ""
				for k in KNOWN_UNUSED:
					if f == k + ".glb" or (f.begins_with(k + "_") and f.get_file().substr(k.get_file().length() + 1, 1).is_valid_int()):
						known = KNOWN_UNUSED[k]
				if known != "":
					print("KNOWN UNUSED  %s (%s)" % [f, known])
				else:
					unref.append(f)
	print("roots (tscn/tres/gd): %d, resources reached: %d, courtyard assets: %d" % [roots, _seen.size(), assets])
	for b in _broken:
		print("BROKEN  ", b)
	for u in unref:
		print("UNREFERENCED  ", u)
	print("==== ref check: %s (%d broken, %d unreferenced) ====" % ["PASS" if _broken.is_empty() and unref.is_empty() else "FAIL", _broken.size(), unref.size()])
	quit(0 if _broken.is_empty() and unref.is_empty() else 1)
