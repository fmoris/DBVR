class_name ZenkaiAnimationLoader
extends RefCounted

const ZENKAI_ANIM_DIR: String = "res://assets/animations/zenkai/"

const BONE_ALIAS_TO_SPA: Dictionary = {
	"Hips": "WAIST",
	"Spine": "SPINE1",
	"Chest": "SPINE2",
	"UpperChest": "SPINE3",
	"Neck": "NECK",
	"Head": "HEAD",
	"LeftShoulder": "CLAVICLE_R",
	"LeftArm": "SHOULDER_R",
	"LeftForeArm": "ELBOW_R",
	"LeftHand": "WRIST_R",
	"RightShoulder": "CLAVICLE_L",
	"RightArm": "SHOULDER_L",
	"RightForeArm": "ELBOW_L",
	"RightHand": "WRIST_L",
	"LeftUpLeg": "THIGH_R",
	"LeftLeg": "CLANK_R",
	"RightUpLeg": "THIGH_L",
	"RightLeg": "CLANK_L",
}

static var _library_cache: Dictionary = {}

var active_library_path: String = ""
var _clips: Dictionary = {}


func load_library(library_path: String) -> bool:
	if library_path.is_empty():
		return false
	active_library_path = library_path
	if _library_cache.has(library_path):
		_clips = _library_cache[library_path]
		return not _clips.is_empty()

	if not FileAccess.file_exists(library_path):
		return false

	var raw_text: String = FileAccess.get_file_as_string(library_path)
	if raw_text.is_empty():
		return false

	var parsed: Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	var root_dict: Dictionary = parsed
	var raw_clips_var: Variant = root_dict.get("clips", {})
	if typeof(raw_clips_var) != TYPE_DICTIONARY:
		return false

	var raw_clips: Dictionary = raw_clips_var
	var compiled_clips: Dictionary = {}

	for clip_key in raw_clips.keys():
		var clip_name: String = String(clip_key)
		var clip_obj_var: Variant = raw_clips[clip_key]
		if typeof(clip_obj_var) != TYPE_DICTIONARY:
			continue
		var clip_obj: Dictionary = clip_obj_var
		var total_frames: float = maxf(float(clip_obj.get("frames", 30.0)), 1.0)
		var fps_val: float = maxf(float(clip_obj.get("fps", 60.0)), 1.0)
		var raw_tracks_var: Variant = clip_obj.get("tracks", {})
		if typeof(raw_tracks_var) != TYPE_DICTIONARY:
			continue

		var raw_tracks: Dictionary = raw_tracks_var
		var compiled_tracks: Dictionary = {}

		for bone_key in raw_tracks.keys():
			var spa_bone: String = String(bone_key)
			var kf_list_var: Variant = raw_tracks[bone_key]
			if typeof(kf_list_var) != TYPE_ARRAY:
				continue
			var kf_list: Array = kf_list_var
			if kf_list.is_empty():
				continue

			var frames_arr: PackedFloat32Array = PackedFloat32Array()
			var quats_arr: Array[Quaternion] = []
			for entry_var in kf_list:
				if typeof(entry_var) != TYPE_DICTIONARY:
					continue
				var entry: Dictionary = entry_var
				var f_val: float = float(entry.get("frame", 0.0))
				var q_var: Variant = entry.get("quat", [])
				if typeof(q_var) == TYPE_ARRAY and (q_var as Array).size() >= 4:
					var q_arr: Array = q_var
					var q: Quaternion = Quaternion(
						float(q_arr[0]),
						float(q_arr[1]),
						float(q_arr[2]),
						float(q_arr[3])
					).normalized()
					frames_arr.append(f_val)
					quats_arr.append(q)

			if not quats_arr.is_empty():
				compiled_tracks[spa_bone] = {
					"frames": frames_arr,
					"quats": quats_arr
				}

		if not compiled_tracks.is_empty():
			compiled_clips[clip_name] = {
				"frames": total_frames,
				"fps": fps_val,
				"duration": total_frames / fps_val,
				"tracks": compiled_tracks
			}

	_library_cache[library_path] = compiled_clips
	_clips = compiled_clips
	return not _clips.is_empty()


func load_default_for_character(is_vegeta: bool, form_name: String = "") -> bool:
	var f_up: String = form_name.to_upper()
	var file_name: String = "goku_base_anims.json"
	if is_vegeta:
		if "SSB" in f_up or "BLUE" in f_up or "EGO" in f_up:
			file_name = "vegeta_ssb_anims.json"
		elif "SUPER" in f_up or "SSJ2" in f_up:
			file_name = "vegeta_super_anims.json"
		else:
			file_name = "vegeta_base_anims.json"
	else:
		if "SSB" in f_up or "BLUE" in f_up or "INSTINTO" in f_up or "UI" in f_up:
			file_name = "goku_ssb_anims.json"
		elif "SSJ3" in f_up:
			file_name = "goku_ssj3_anims.json"
		elif "SSJ" in f_up:
			file_name = "goku_ssj_anims.json"
		else:
			file_name = "goku_base_anims.json"
	return load_library(ZENKAI_ANIM_DIR + file_name)


func has_clip(clip_name: String) -> bool:
	return _clips.has(clip_name)


func get_clip_duration(clip_name: String, default_duration: float = 0.5) -> float:
	if not _clips.has(clip_name):
		return default_duration
	var clip_dict: Dictionary = _clips[clip_name]
	return float(clip_dict.get("duration", default_duration))


func sample_clip_bone_rotation(
	clip_name: String,
	bone_alias: String,
	normalized_time: float,
	fallback_rot: Quaternion
) -> Quaternion:
	if not _clips.has(clip_name):
		return fallback_rot
	var clip_dict: Dictionary = _clips[clip_name]
	var tracks: Dictionary = clip_dict["tracks"]
	var spa_bone: String = String(BONE_ALIAS_TO_SPA.get(bone_alias, bone_alias))
	if not tracks.has(spa_bone):
		return fallback_rot

	var track_data: Dictionary = tracks[spa_bone]
	var frames_arr: PackedFloat32Array = track_data["frames"]
	var quats_arr: Array = track_data["quats"]
	var count: int = quats_arr.size()
	if count == 0:
		return fallback_rot
	if count == 1:
		return quats_arr[0]

	var total_frames: float = float(clip_dict["frames"])
	var target_frame: float = clampf(normalized_time, 0.0, 1.0) * total_frames

	if target_frame <= frames_arr[0]:
		return quats_arr[0]
	if target_frame >= frames_arr[count - 1]:
		return quats_arr[count - 1]

	for i in range(count - 1):
		var f0: float = frames_arr[i]
		var f1: float = frames_arr[i + 1]
		if target_frame >= f0 and target_frame <= f1:
			var span: float = f1 - f0
			if span <= 0.0001:
				return quats_arr[i]
			var t: float = clampf((target_frame - f0) / span, 0.0, 1.0)
			var q0: Quaternion = quats_arr[i]
			var q1: Quaternion = quats_arr[i + 1]
			return q0.slerp(q1, t).normalized()

	return quats_arr[count - 1]


func sample_clip_bone_delta_euler(
	clip_name: String,
	bone_alias: String,
	normalized_time: float
) -> Vector3:
	if not _clips.has(clip_name):
		return Vector3.ZERO
	var q0: Quaternion = sample_clip_bone_rotation(clip_name, bone_alias, 0.0, Quaternion.IDENTITY)
	var qt: Quaternion = sample_clip_bone_rotation(clip_name, bone_alias, normalized_time, q0)
	var delta_q: Quaternion = (q0.inverse() * qt).normalized()
	return delta_q.get_euler()
