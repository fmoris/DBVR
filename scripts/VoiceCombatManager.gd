extends Node

## Gestor de micrófono VR y bonos de combate por voz en 2 Fases (Fase 1: Gritos/Kiai nativo, Fase 2: Vosk Latino/Japonés).
## Soporta cantos divididos en Fase 1 (carga: "kamehame", "galick", "final") + Fase 2 (remate: "haa", "ho", "flash" o grito).
## Mantiene zero-allocation en _process() reutilizando el buffer de muestras.

signal shout_started(intensity: float)
signal shout_ended()
signal kiai_burst_detected(intensity: float)
signal power_chant_detected(power_id: String, confidence: float)
signal power_phase1_chant_detected(power_id: String)
signal power_phase2_release_detected(power_id: String, is_perfect_combo: bool)
signal mic_calibration_finished(noise_floor_db: float)

const MIC_BUS_NAME := &"MicCapture"
const CALIBRATION_DURATION_SEC: float = 1.5
const SHOUT_HOLD_MIN_SEC: float = 0.25
const SHOUT_RELEASE_HYSTERESIS_SEC: float = 0.30
const KIAI_COOLDOWN_SEC: float = 1.80
const KIAI_BONUS_WINDOW_SEC: float = 0.65
const POWER_CHANT_WINDOW_SEC: float = 4.5
const PHASE2_RELEASE_WINDOW_SEC: float = 1.25

## Fase 1 (Carga): Prefijos en Latino / Japonés -> ID interno de poder
const PHASE1_CHARGE_KEYWORDS: Dictionary = {
	"kamehame": "kamehameha",
	"super kamehame": "super_kamehameha",
	"diez veces kamehame": "kamehameha_x10",
	"juubai kamehame": "kamehameha_x10",
	"galick": "galick_ho",
	"gyarikku": "galick_ho",
	"final": "final_flash",
	"resplandor": "final_flash",
	"big bang": "big_bang",
	"ataque": "big_bang",
	"genki": "genkidama",
	"energia": "genkidama",
	"kaio": "kaioken",
	"explosion": "final_explosion",
}

## Fase 2 (Remate): Palabras de liberación / grito final -> poderes compatibles ("" = cualquiera)
const PHASE2_FIRE_KEYWORDS: Dictionary = {
	"ha": "",
	"haa": "",
	"haaa": "",
	"ho": "galick_ho",
	"hou": "galick_ho",
	"flash": "final_flash",
	"dama": "genkidama",
	"ken": "kaioken",
	"attack": "big_bang",
	"bang": "big_bang",
}

## Fallback de frase completa en Latino / Japonés -> ID interno de poder
const KEYWORD_TO_POWER_ID: Dictionary = {
	"kamehameha": "kamehameha",
	"super kamehameha": "super_kamehameha",
	"diez veces kamehameha": "kamehameha_x10",
	"juubai kamehameha": "kamehameha_x10",
	"genkidama": "genkidama",
	"kaioken": "kaioken",
	"galick ho": "galick_ho",
	"gyarikku hou": "galick_ho",
	"big bang": "big_bang",
	"ataque big bang": "big_bang",
	"final flash": "final_flash",
	"resplandor final": "final_flash",
	"final explosion": "final_explosion",
	"explosion final": "final_explosion",
}

@export var mic_enabled: bool = true
@export var sensitivity_offset_db: float = 0.0

var _native_voice_plugin: Object = null
var _using_native_plugin: bool = false
var _mic_player: AudioStreamPlayer = null
var _capture_effect: AudioEffectCapture = null
var _sample_buffer: PackedVector2Array = PackedVector2Array()

var _permission_requested: bool = false
var _permission_granted: bool = false
var _mic_started: bool = false

# Calibración y estado de energía vocal
var _is_calibrating: bool = false
var _calibration_timer: float = 0.0
var _calibration_db_sum: float = 0.0
var _calibration_samples: int = 0
var noise_floor_db: float = -45.0
var shout_threshold_db: float = -28.0
var kiai_threshold_db: float = -22.0

var _smoothed_db: float = -60.0
var _shout_hold_timer: float = 0.0
var _shout_release_timer: float = 0.0
var _is_shouting: bool = false
var _shout_intensity: float = 0.0

var _kiai_cooldown_timer: float = 0.0
var _kiai_bonus_window_timer: float = 0.0
var _kiai_bonus_pending: bool = false

# Estado de canto en 2 Fases para Súper Poderes
var _active_charging_tech: String = ""
var _phase1_power_id: String = ""
var _phase1_timer: float = 0.0
var _phase2_fire_power_id: String = ""
var _phase2_fire_timer: float = 0.0

# Overrides para pruebas de escritorio / DesktopXRSimulator
var _debug_shout_active: bool = false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return

	if Engine.has_singleton("DBZVRVoice"):
		_native_voice_plugin = Engine.get_singleton("DBZVRVoice")
		_using_native_plugin = true
		_connect_native_plugin()

	_check_and_request_permissions()


func _exit_tree() -> void:
	if _using_native_plugin and _native_voice_plugin and _native_voice_plugin.has_method("stopListening"):
		_native_voice_plugin.call("stopListening")
	if _mic_player and is_instance_valid(_mic_player):
		_mic_player.stop()


func _process(delta: float) -> void:
	if _kiai_cooldown_timer > 0.0:
		_kiai_cooldown_timer = maxf(_kiai_cooldown_timer - delta, 0.0)
	if _kiai_bonus_window_timer > 0.0:
		_kiai_bonus_window_timer = maxf(_kiai_bonus_window_timer - delta, 0.0)
		if _kiai_bonus_window_timer <= 0.0:
			_kiai_bonus_pending = false
	if _phase1_timer > 0.0:
		_phase1_timer = maxf(_phase1_timer - delta, 0.0)
		if _phase1_timer <= 0.0:
			_phase1_power_id = ""
	if _phase2_fire_timer > 0.0:
		_phase2_fire_timer = maxf(_phase2_fire_timer - delta, 0.0)
		if _phase2_fire_timer <= 0.0:
			_phase2_fire_power_id = ""

	if _debug_shout_active:
		_update_shout_state(-10.0, delta)
		return

	if not mic_enabled:
		_update_shout_state(-80.0, delta)
		return

	if not _permission_granted:
		if OS.get_name() == "Android":
			if OS.get_granted_permissions().has("android.permission.RECORD_AUDIO"):
				_permission_granted = true
				_start_audio_capture()
		return

	if not _mic_started:
		_start_audio_capture()
		return

	if _using_native_plugin:
		return

	if _capture_effect == null:
		return

	var avail: int = _capture_effect.get_frames_available()
	if avail <= 0:
		return

	_sample_buffer = _capture_effect.get_buffer(avail)
	var rms_db: float = _compute_rms_db(_sample_buffer)
	_process_rms_db(rms_db, delta)


func _check_and_request_permissions() -> void:
	if OS.get_name() != "Android":
		_permission_granted = true
		_start_audio_capture()
		return

	var granted: PackedStringArray = OS.get_granted_permissions()
	if granted.has("android.permission.RECORD_AUDIO"):
		_permission_granted = true
		_start_audio_capture()
	elif not _permission_requested:
		_permission_requested = true
		OS.request_permission("android.permission.RECORD_AUDIO")


func _start_audio_capture() -> void:
	if _mic_started or not mic_enabled:
		return

	if _using_native_plugin and _native_voice_plugin:
		if _native_voice_plugin.has_method("startListening"):
			_native_voice_plugin.call("startListening")
		_mic_started = true
		recalibrate_noise_floor()
		return

	var bus_idx: int = AudioServer.get_bus_index(MIC_BUS_NAME)
	if bus_idx < 0:
		push_warning("[VoiceCombatManager] Bus '%s' no encontrado en AudioBusLayout." % MIC_BUS_NAME)
		return

	if AudioServer.get_bus_effect_count(bus_idx) > 0:
		var fx: AudioEffect = AudioServer.get_bus_effect(bus_idx, 0)
		if fx is AudioEffectCapture:
			_capture_effect = fx as AudioEffectCapture

	if _capture_effect == null:
		push_warning("[VoiceCombatManager] AudioEffectCapture no encontrado en bus '%s'." % MIC_BUS_NAME)
		return

	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.name = "VRMicInputPlayer"
		_mic_player.bus = MIC_BUS_NAME
		_mic_player.stream = AudioStreamMicrophone.new()
		add_child(_mic_player)

	_mic_player.play()
	_mic_started = true
	recalibrate_noise_floor()


func _connect_native_plugin() -> void:
	if not _native_voice_plugin:
		return
	if _native_voice_plugin.has_signal("voice_energy_updated"):
		_native_voice_plugin.connect("voice_energy_updated", Callable(self, "_on_native_energy_updated"))
	if _native_voice_plugin.has_signal("keyword_detected"):
		_native_voice_plugin.connect("keyword_detected", Callable(self, "_on_native_keyword_detected"))


func _on_native_energy_updated(rms_db: float) -> void:
	_process_rms_db(rms_db, get_process_delta_time())


func _on_native_keyword_detected(keyword: String, confidence: float) -> void:
	var normalized: String = keyword.strip_edges().to_lower()
	if normalized.is_empty():
		return

	if PHASE1_CHARGE_KEYWORDS.has(normalized):
		var p1_id: String = PHASE1_CHARGE_KEYWORDS[normalized]
		_phase1_power_id = p1_id
		_phase1_timer = POWER_CHANT_WINDOW_SEC
		power_phase1_chant_detected.emit(p1_id)
		power_chant_detected.emit(p1_id, confidence)
		return

	if PHASE2_FIRE_KEYWORDS.has(normalized):
		var p2_target: String = PHASE2_FIRE_KEYWORDS[normalized]
		_phase2_fire_power_id = p2_target if not p2_target.is_empty() else _active_charging_tech
		_phase2_fire_timer = PHASE2_RELEASE_WINDOW_SEC
		var has_p1: bool = not _phase1_power_id.is_empty() and _phase1_timer > 0.0
		power_phase2_release_detected.emit(_phase2_fire_power_id, has_p1)
		return

	var full_id: String = KEYWORD_TO_POWER_ID.get(normalized, "")
	if not full_id.is_empty():
		_phase1_power_id = full_id
		_phase1_timer = POWER_CHANT_WINDOW_SEC
		_phase2_fire_power_id = full_id
		_phase2_fire_timer = POWER_CHANT_WINDOW_SEC
		power_chant_detected.emit(full_id, confidence)


func recalibrate_noise_floor() -> void:
	_is_calibrating = true
	_calibration_timer = 0.0
	_calibration_db_sum = 0.0
	_calibration_samples = 0


func set_mic_enabled(enabled: bool) -> void:
	mic_enabled = enabled
	if not enabled:
		_set_shouting(false, 0.0)
		if _mic_player and is_instance_valid(_mic_player) and _mic_player.playing:
			_mic_player.stop()
		if _using_native_plugin and _native_voice_plugin and _native_voice_plugin.has_method("stopListening"):
			_native_voice_plugin.call("stopListening")
		_mic_started = false
	elif _permission_granted:
		_start_audio_capture()


func _compute_rms_db(samples: PackedVector2Array) -> float:
	var n: int = samples.size()
	if n <= 0:
		return -80.0
	var sum_sq: float = 0.0
	for i in range(n):
		var v: Vector2 = samples[i]
		var mono: float = (v.x + v.y) * 0.5
		sum_sq += mono * mono
	var rms: float = sqrt(sum_sq / float(n))
	if rms <= 0.00001:
		return -80.0
	return clampf(linear_to_db(rms), -80.0, 0.0)


func _process_rms_db(rms_db: float, delta: float) -> void:
	if _is_calibrating:
		_calibration_timer += delta
		_calibration_db_sum += rms_db
		_calibration_samples += 1
		if _calibration_timer >= CALIBRATION_DURATION_SEC:
			_is_calibrating = false
			if _calibration_samples > 0:
				noise_floor_db = clampf(_calibration_db_sum / float(_calibration_samples), -65.0, -25.0)
			shout_threshold_db = clampf(noise_floor_db + 12.0 + sensitivity_offset_db, -36.0, -12.0)
			kiai_threshold_db = clampf(noise_floor_db + 16.0 + sensitivity_offset_db, -32.0, -8.0)
			mic_calibration_finished.emit(noise_floor_db)
		return

	# Detección de Kiai / Remate "¡HAAA!" (pico vocal súbito)
	if rms_db >= kiai_threshold_db and (rms_db - _smoothed_db) >= 5.5 and _kiai_cooldown_timer <= 0.0:
		_kiai_cooldown_timer = KIAI_COOLDOWN_SEC
		_kiai_bonus_window_timer = KIAI_BONUS_WINDOW_SEC
		_kiai_bonus_pending = true
		_phase2_fire_power_id = _active_charging_tech
		_phase2_fire_timer = PHASE2_RELEASE_WINDOW_SEC
		var kiai_int: float = clampf((rms_db - kiai_threshold_db) / 14.0, 0.35, 1.0)
		kiai_burst_detected.emit(kiai_int)

	_smoothed_db = lerpf(_smoothed_db, rms_db, clampf(delta * 12.0, 0.0, 1.0))
	_update_shout_state(rms_db, delta)


func _update_shout_state(rms_db: float, delta: float) -> void:
	if rms_db >= shout_threshold_db:
		_shout_release_timer = 0.0
		_shout_hold_timer += delta
		var intensity: float = clampf((rms_db - shout_threshold_db) / 16.0, 0.25, 1.0)
		if _shout_hold_timer >= SHOUT_HOLD_MIN_SEC:
			_set_shouting(true, intensity)
	else:
		_shout_hold_timer = 0.0
		if _is_shouting:
			_shout_release_timer += delta
			if _shout_release_timer >= SHOUT_RELEASE_HYSTERESIS_SEC:
				_set_shouting(false, 0.0)


func _set_shouting(active: bool, intensity: float) -> void:
	var was_shouting: bool = _is_shouting
	_is_shouting = active
	_shout_intensity = intensity if active else 0.0
	if active and not was_shouting:
		shout_started.emit(_shout_intensity)
	elif not active and was_shouting:
		shout_ended.emit()


## --- API Pública para Squads de Combate ---

func notify_super_charge_started(tech_name: String) -> void:
	_active_charging_tech = tech_name.strip_edges().to_lower().replace(" ", "_")


func notify_super_charge_ended() -> void:
	_active_charging_tech = ""


func _tech_matches(stored_id: String, tech_norm: String) -> bool:
	if stored_id.is_empty():
		return false
	return stored_id == tech_norm or tech_norm.contains(stored_id) or stored_id.contains(tech_norm)


func get_charge_speed_multiplier(tech_name: String) -> float:
	var norm: String = tech_name.strip_edges().to_lower().replace(" ", "_")
	if not _phase1_power_id.is_empty() and _phase1_timer > 0.0 and _tech_matches(_phase1_power_id, norm):
		return 1.10
	if is_shouting():
		return 1.05
	return 1.0


func is_shouting() -> bool:
	return _is_shouting or _debug_shout_active


func get_shout_intensity() -> float:
	return _shout_intensity


func consume_kiai_melee_bonus() -> float:
	if _kiai_bonus_pending and _kiai_bonus_window_timer > 0.0:
		_kiai_bonus_pending = false
		_kiai_bonus_window_timer = 0.0
		return 0.12
	if _is_shouting and _kiai_cooldown_timer <= 0.0:
		_kiai_cooldown_timer = KIAI_COOLDOWN_SEC
		return 0.10
	return 0.0


func consume_voice_power_bonus(tech_name: String) -> Dictionary:
	var norm: String = tech_name.strip_edges().to_lower().replace(" ", "_")
	var has_p1: bool = not _phase1_power_id.is_empty() and _phase1_timer > 0.0 and _tech_matches(_phase1_power_id, norm)
	var has_p2_word: bool = _phase2_fire_timer > 0.0 and (_phase2_fire_power_id.is_empty() or _tech_matches(_phase2_fire_power_id, norm))
	var has_p2_shout: bool = is_shouting() or (_kiai_bonus_pending and _kiai_bonus_window_timer > 0.0)
	var has_p2: bool = has_p2_word or has_p2_shout

	if has_p1:
		_phase1_power_id = ""
		_phase1_timer = 0.0
	if has_p2_word:
		_phase2_fire_power_id = ""
		_phase2_fire_timer = 0.0

	if has_p1 and has_p2:
		power_phase2_release_detected.emit(norm, true)
		return {"active": true, "ki_cost_mult": 0.85, "damage_mult": 1.20, "source": "perfect_2phase"}
	if has_p1:
		return {"active": true, "ki_cost_mult": 0.90, "damage_mult": 1.05, "source": "phase1_charge"}
	if has_p2:
		power_phase2_release_detected.emit(norm, false)
		return {"active": true, "ki_cost_mult": 0.95, "damage_mult": 1.08, "source": "phase2_shout"}
	return {"active": false, "ki_cost_mult": 1.0, "damage_mult": 1.0, "source": "none"}


## --- Hooks para DesktopXRSimulator y Tests ---

func set_debug_shout(active: bool) -> void:
	_debug_shout_active = active
	if active:
		_set_shouting(true, 0.85)
	else:
		_set_shouting(false, 0.0)


func trigger_debug_kiai() -> void:
	_kiai_bonus_pending = true
	_kiai_bonus_window_timer = KIAI_BONUS_WINDOW_SEC
	_phase2_fire_power_id = _active_charging_tech
	_phase2_fire_timer = PHASE2_RELEASE_WINDOW_SEC
	kiai_burst_detected.emit(0.9)


func trigger_debug_power_chant(power_id: String) -> void:
	_on_native_keyword_detected(power_id, 1.0)
