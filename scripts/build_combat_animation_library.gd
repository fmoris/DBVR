extends SceneTree

const BONE_MAPPING: Dictionary = {
	"mixamorig_Hips": "Hips",
	"mixamorig_Spine": "Spine",
	"mixamorig_Spine1": "Chest",
	"mixamorig_Spine2": "UpperChest",
	"mixamorig_Neck": "Neck",
	"mixamorig_Head": "Head",
	"mixamorig_LeftShoulder": "LeftShoulder",
	"mixamorig_LeftArm": "LeftArm",
	"mixamorig_LeftForeArm": "LeftForeArm",
	"mixamorig_LeftHand": "LeftHand",
	"mixamorig_RightShoulder": "RightShoulder",
	"mixamorig_RightArm": "RightArm",
	"mixamorig_RightForeArm": "RightForeArm",
	"mixamorig_RightHand": "RightHand",
	"mixamorig_LeftUpLeg": "LeftUpLeg",
	"mixamorig_LeftLeg": "LeftLeg",
	"mixamorig_LeftFoot": "LeftFoot",
	"mixamorig_LeftToeBase": "LeftToes",
	"mixamorig_RightUpLeg": "RightUpLeg",
	"mixamorig_RightLeg": "RightLeg",
	"mixamorig_RightFoot": "RightFoot",
	"mixamorig_RightToeBase": "RightToes"
}

func _init() -> void:
	var library = AnimationLibrary.new()

	var anim_sources = {
		"bouncing_fight_idle": "res://assets/animations/bouncing_fight_idle.fbx",
		"fighting_idle": "res://assets/animations/fighting_idle.fbx"
	}

	for anim_name in anim_sources:
		var path = anim_sources[anim_name]
		var scene: PackedScene = load(path)
		if not scene:
			print("❌ Error al cargar: ", path)
			continue

		var inst = scene.instantiate()
		var player: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if not player:
			print("❌ No se encontró AnimationPlayer en ", path)
			continue

		var src_anim: Animation = player.get_animation("mixamo_com")
		if not src_anim:
			print("❌ No se encontró 'mixamo_com' en ", path)
			continue

		var new_anim = Animation.new()
		new_anim.length = src_anim.length
		new_anim.loop_mode = Animation.LOOP_LINEAR
		new_anim.step = src_anim.step

		var mapped_count = 0
		for t in range(src_anim.get_track_count()):
			var track_path = String(src_anim.track_get_path(t))
			var track_type = src_anim.track_get_type(t)

			# Analizar nombre del hueso
			var parts = track_path.split(":")
			if parts.size() < 2:
				continue
			var orig_bone = parts[1]

			if BONE_MAPPING.has(orig_bone):
				var target_bone = BONE_MAPPING[orig_bone]
				var new_track_path = NodePath("Skeleton3D:" + target_bone)

				var new_track_idx = new_anim.add_track(track_type)
				new_anim.track_set_path(new_track_idx, new_track_path)
				new_anim.track_set_interpolation_type(new_track_idx, src_anim.track_get_interpolation_type(t))

				var key_count = src_anim.track_get_key_count(t)
				for k in range(key_count):
					var key_time = src_anim.track_get_key_time(t, k)
					var key_val = src_anim.track_get_key_value(t, k)
					var key_trans = src_anim.track_get_key_transition(t, k)
					new_anim.track_insert_key(new_track_idx, key_time, key_val, key_trans)

				mapped_count += 1

		library.add_animation(anim_name, new_anim)
		print("✅ Animación '%s' procesada con éxito (%d tracks mapeados, %.2fs, loop activado)" % [
			anim_name, mapped_count, new_anim.length
		])

	var err = ResourceSaver.save(library, "res://resources/DBVR_Combat_Animations.tres")
	if err == OK:
		print("🎉 Guardado res://resources/DBVR_Combat_Animations.tres exitosamente!")
	else:
		print("❌ Error al guardar AnimationLibrary: ", err)

	quit(0)
