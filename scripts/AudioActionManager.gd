extends Node

## Gestor centralizado de audio por acciones (audio_actions.json).
## Precarga y cachea todos los streams en _ready() para evitar alocaciones y tirones en VR (90 FPS).

const ACTIONS_JSON_PATH := "res://assets/audio/audio_actions.json"

var _actions: Dictionary = {} # action_id (String) -> Array[AudioStream]
var _stream_cache: Dictionary = {} # res_path (String) -> AudioStream


func _ready() -> void:
	reload_actions()


func reload_actions() -> void:
	_actions.clear()
	if not FileAccess.file_exists(ACTIONS_JSON_PATH):
		push_warning("[AudioActionManager] No se encontró %s" % ACTIONS_JSON_PATH)
		return

	var file := FileAccess.open(ACTIONS_JSON_PATH, FileAccess.READ)
	if not file:
		push_warning("[AudioActionManager] No se pudo abrir %s" % ACTIONS_JSON_PATH)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary) or not parsed.has("actions"):
		push_warning("[AudioActionManager] Formato inválido en %s" % ACTIONS_JSON_PATH)
		return

	var raw_actions: Dictionary = parsed["actions"]
	var loaded_count: int = 0
	for action_id in raw_actions.keys():
		var entry: Variant = raw_actions[action_id]
		if not (entry is Dictionary):
			continue
		var sound_paths: Variant = entry.get("sounds", [])
		if not (sound_paths is Array) or sound_paths.is_empty():
			continue

		var streams: Array[AudioStream] = []
		for path_var in sound_paths:
			var res_path := str(path_var)
			if res_path.is_empty():
				continue
			var stream := _load_cached(res_path)
			if stream:
				streams.append(stream)
				loaded_count += 1
		if not streams.is_empty():
			_actions[str(action_id)] = streams

	print("[AudioActionManager] Cargadas %d acciones con %d streams pre-cacheados." % [_actions.size(), loaded_count])


func _load_cached(res_path: String) -> AudioStream:
	if _stream_cache.has(res_path):
		return _stream_cache[res_path]
	if not ResourceLoader.exists(res_path):
		push_warning("[AudioActionManager] Audio no encontrado: %s" % res_path)
		return null
	var res := load(res_path)
	if res is AudioStream:
		_stream_cache[res_path] = res
		return res
	return null


func has_action_sounds(action_id: String) -> bool:
	return _actions.has(action_id) and not (_actions[action_id] as Array).is_empty()


func get_random_stream(action_id: String, fallback: AudioStream = null) -> AudioStream:
	if _actions.has(action_id):
		var streams: Array = _actions[action_id]
		if not streams.is_empty():
			return streams[randi() % streams.size()]
	return fallback


func play_action(action_id: String, player: Node, fallback: AudioStream = null, loop_stream: bool = false) -> bool:
	if not player or not is_instance_valid(player):
		return false
	var chosen := get_random_stream(action_id, fallback)
	if not chosen:
		return false
	_apply_loop_if_supported(chosen, loop_stream)
	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).stream = chosen
		(player as AudioStreamPlayer).play()
		return true
	elif player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).stream = chosen
		(player as AudioStreamPlayer3D).play()
		return true
	return false


func get_character_action_id(character_name: String, suffix: String) -> String:
	var lower := character_name.to_lower()
	if "vegeta" in lower:
		return "vegeta." + suffix
	if "goku" in lower:
		return "goku." + suffix
	return "common." + suffix


func _apply_loop_if_supported(stream: AudioStream, should_loop: bool) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = should_loop
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = should_loop
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if should_loop else AudioStreamWAV.LOOP_DISABLED
