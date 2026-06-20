@tool
extends Node3D

# --- Parámetros de Posicionamiento Fijo (Espacio Local de Cámara) ---
@export var distance_from_camera: float = 1.0
@export var horizontal_offset: float = 0.3 # Centrado en el eje horizontal de la vista
@export var vertical_offset: float = -0.3   # Situado ligeramente abajo para evitar obstruir el combate

@onready var sub_viewport: SubViewport = $SubViewport
@onready var hud_mesh: MeshInstance3D = $HUDMesh

# Referencias a nodos de la UI interna (usamos get_node_or_null para seguridad en modo @tool)
@onready var ki_bar: ProgressBar = get_node_or_null("SubViewport/HUDLayout/MainPanel/MarginContainer/VBoxContainer/KiSection/KiBar")
@onready var ki_value_label: Label = get_node_or_null("SubViewport/HUDLayout/MainPanel/MarginContainer/VBoxContainer/KiSection/Labels/Value")
@onready var np_bar: ProgressBar = get_node_or_null("SubViewport/HUDLayout/MainPanel/MarginContainer/VBoxContainer/NPSection/NPBar")
@onready var np_value_label: Label = get_node_or_null("SubViewport/HUDLayout/MainPanel/MarginContainer/VBoxContainer/NPSection/Labels/Value")
@onready var phase_status_label: Label = get_node_or_null("SubViewport/HUDLayout/MainPanel/MarginContainer/VBoxContainer/PhaseStatus")

# --- Estado del Combate Dinámico (Inicia Ki en 50%) ---
var ki_max: float = 100.0
var ki_current: float = 50.0 # Inicializado a la mitad de Ki (50.0 / 100.0) a solicitud de Francis
var np_max: float = 20000.0
var np_current: float = 9000.0

var is_recharging: bool = false
var is_heavy_recharge: bool = false

# --- Referencias y Historial de Depuración VR ---
var debug_logs_label: RichTextLabel = null
var live_joints_label: Label = null
var debug_history: Array[String] = []


func _ready() -> void:
	if not sub_viewport or not hud_mesh:
		return
	# Configurar el material dinámico para evitar fallos de vinculación en .tscn
	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED # Glow perfecto sin sombras
	mat.albedo_texture = sub_viewport.get_texture()
	hud_mesh.material_override = mat

	if not Engine.is_editor_hint():
		# Llamamos diferido para dar tiempo a que la cámara y el árbol de nodos se inicialicen completamente
		call_deferred("_reparent_to_camera")
		call_deferred("_setup_vr_debugger")

func _reparent_to_camera() -> void:
	var camera = get_viewport().get_camera_3d()
	if camera:
		# Si ya somos hijos de la cámara, no hace falta reparentar
		if get_parent() != camera:
			var old_parent = get_parent()
			if old_parent:
				old_parent.remove_child(self)
			camera.add_child(self)
		
		# Establecer la transformación local rígida (abajo a la izquierda y al frente)
		position = Vector3(horizontal_offset, vertical_offset, -distance_from_camera)
		rotation = Vector3.ZERO
		
		# Forzar que el procesamiento continúe en runtime para el cálculo de estadísticas
		set_process(true)
		
		# Inicializar visualmente en 0
		update_ki(ki_current, ki_max)
		update_power_level(np_current, np_max)
		
		# Conexión dinámica con el árbol de decisiones biométrico
		var gesture_tree = get_node_or_null("/root/cell_games_arena/GesturePhaseTree")
		if not gesture_tree:
			gesture_tree = get_tree().root.find_child("GesturePhaseTree", true, false)
			
		if gesture_tree:
			gesture_tree.ki_recharge_started.connect(_on_recharge_started)
			gesture_tree.ki_recharge_stopped.connect(_on_recharge_stopped)
			gesture_tree.ki_blast_fired.connect(_on_ki_blast_fired)
			if gesture_tree.has_signal("ki_blast_charging"):
				gesture_tree.ki_blast_charging.connect(_on_ki_blast_charging)
			if gesture_tree.has_signal("gesture_logged"):
				gesture_tree.gesture_logged.connect(log_gesture_event)
			if gesture_tree.has_signal("hand_states_updated"):
				gesture_tree.hand_states_updated.connect(_on_hand_states_updated)
			print("[VRHUD] Conexión establecida con GesturePhaseTree y su consola de depuración VR.")


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_update_editor_position()
		return
		
	# Bucle de juego en runtime: procesar únicamente el incremento y consumo de Ki/NP
	_update_combat_stats(delta)

func _update_editor_position() -> void:
	var camera: Camera3D = null
	var tree_root = get_tree().edited_scene_root
	if tree_root:
		camera = tree_root.find_child("XRCamera3D", true, false) as Camera3D
	if not camera:
		camera = get_viewport().get_camera_3d()

	if not camera:
		return

	var local_offset = Vector3(horizontal_offset, vertical_offset, -distance_from_camera)
	global_position = camera.global_transform * local_offset
	global_transform.basis = camera.global_transform.basis

# --- Callbacks de Señales del Gesto de Combate ---

func _on_recharge_started(is_heavy: bool) -> void:
	is_recharging = true
	is_heavy_recharge = is_heavy

func _on_recharge_stopped() -> void:
	is_recharging = false
	is_heavy_recharge = false

func _on_ki_blast_fired(hand_side: int, is_charged: bool) -> void:
	if not is_charged:
		var cost = 8.0 # Disparo rápido consume un mínimo de 8 de Ki base
		if ki_current >= cost:
			ki_current -= cost
			update_ki(ki_current, ki_max)
			print("[VRHUD] Ki Blast Normal disparado por mano %s. Coste base deducido. Ki restante: %.1f" % ["Izquierda" if hand_side == 0 else "Derecha", ki_current])
		else:
			print("[VRHUD] ¡Ki insuficiente para disparar ráfagas rápidas de Ki Blast!")
	else:
		# Para disparos cargados, el Ki ya fue drenado progresivamente a 5/s durante la carga
		print("[VRHUD] ¡KI BLAST CARGADO disparado por mano %s! Ki restante: %.1f" % ["Izquierda" if hand_side == 0 else "Derecha", ki_current])

func _on_ki_blast_charging(hand_side: int, charge_time: float, delta: float) -> void:
	# Drenar de forma continua 5 de Ki por segundo de forma simétrica durante la carga
	if charge_time < 2.5:
		ki_current = max(ki_current - 5.0 * delta, 0.0)
		update_ki(ki_current, ki_max)

func _update_combat_stats(delta: float) -> void:
	if is_recharging:
		var recharge_speed = 35.0 if is_heavy_recharge else 12.0
		ki_current = min(ki_current + recharge_speed * delta, ki_max)
		
		# Incrementar NP dinámicamente según la intensidad de la carga (tope del 85% para no alcanzar el máximo solo cargando)
		var np_cap = np_max * 0.85
		if is_heavy_recharge:
			np_current = min(np_current + 1800.0 * delta, np_cap)
		else:
			np_current = min(np_current + 400.0 * delta, np_cap)
			
		update_ki(ki_current, ki_max)
		update_power_level(np_current, np_max)
	else:
		# Enfriamiento sutil del Nivel de Poder cuando no se está cargando energía
		if np_current > 9000.0:
			np_current = max(np_current - 200.0 * delta, 9000.0)
			update_power_level(np_current, np_max)

# --- APIs Públicas para Actualización de la Interfaz ---

func update_ki(current: float, max_val: float) -> void:
	if ki_bar:
		ki_bar.max_value = max_val
		ki_bar.value = current
	if ki_value_label:
		ki_value_label.text = "%d / %d" % [int(current), int(max_val)]

func update_power_level(current: float, max_val: float) -> void:
	if np_bar:
		np_bar.max_value = max_val
		np_bar.value = current
	if np_value_label:
		np_value_label.text = "%s" % format_number_with_commas(int(current))

func update_status_text(text: String, color: Color = Color(0.9, 0.9, 0.9)) -> void:
	if phase_status_label:
		phase_status_label.text = text
		phase_status_label.label_settings.font_color = color

# Helper para añadir comas a miles en GDScript
func format_number_with_commas(n: int) -> String:
	var s = str(n)
	var res = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		count += 1
		if count == 3 and i > 0:
			res = "," + res
			count = 0
	return res

# --- Consola Holográfica Depuradora de Gestos (Inyección Procedimental) ---

## Instancia e inyecta dinámicamente la consola RichTextLabel en la UI del Viewport
func _setup_vr_debugger() -> void:
	var vbox = get_node_or_null("SubViewport/HUDLayout/MainPanel/MarginContainer/VBoxContainer")
	if vbox:
		# Crear el RichTextLabel dinámicamente
		debug_logs_label = RichTextLabel.new()
		debug_logs_label.name = "GestureDebuggerPanel"
		debug_logs_label.bbcode_enabled = true
		debug_logs_label.fit_content = true
		debug_logs_label.custom_minimum_size = Vector2(0, 100)
		
		# Estilo de caja premium: panel semi-transparente oscuro tipo consola
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.01, 0.01, 0.03, 0.65) # Consola oscura translúcida
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.set_content_margin_all(8)
		
		debug_logs_label.add_theme_stylebox_override("normal", style)
		
		# Forzar tipografía compacta y de alta definición para visores VR
		debug_logs_label.add_theme_font_size_override("normal_font_size", 12)
		debug_logs_label.add_theme_font_size_override("bold_font_size", 12)
		vbox.add_child(debug_logs_label)
		
		# Crear la etiqueta de estado de manos en vivo dinámicamente debajo de la consola
		live_joints_label = Label.new()
		live_joints_label.name = "LiveHandStatesLabel"
		live_joints_label.text = "L: DESCONECTADA\nR: DESCONECTADA"
		live_joints_label.add_theme_font_size_override("font_size", 11)
		live_joints_label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85, 0.85))
		vbox.add_child(live_joints_label)
		
		log_gesture_event("Consola Holográfica VR inicializada con éxito.", "success")
		print("[VRHUD] Debugger Panel y Live Tracker inyectados procedimentalmente con éxito en la UI interna.")

func _on_hand_states_updated(left_desc: String, right_desc: String) -> void:
	if live_joints_label:
		live_joints_label.text = "L: %s\nR: %s" % [left_desc, right_desc]

## Agrega, formatea con BBCode y actualiza un log de eventos en el panel flotante
func log_gesture_event(msg: String, type: String = "info") -> void:

	# Obtener marca de hora actual del sistema [HH:MM:SS]
	var time_dict = Time.get_time_dict_from_system()
	var time_str = "%02d:%02d:%02d" % [time_dict.hour, time_dict.minute, time_dict.second]
	
	# Formato de colores específicos para alta legibilidad en Quest 3
	var color_hex = "00ccff" # Celeste de base (info)
	match type:
		"success": color_hex = "00ff88" # Verde Ki brillante
		"info": color_hex = "00ccff"    # Celeste Ki
		"warning": color_hex = "ffcc00" # Amarillo
		"error": color_hex = "ff3344"   # Rojo Ki
		
	var log_line = "[color=#666677][%s][/color] [color=#%s]%s[/color]" % [time_str, color_hex, msg]
	debug_history.append(log_line)
	
	# Mantener un búfer circular de los últimos 4 eventos
	if debug_history.size() > 4:
		debug_history.remove_at(0)
		
	# Renderizar el búfer en la pantalla del visor
	if debug_logs_label:
		debug_logs_label.text = ""
		for line in debug_history:
			debug_logs_label.append_text(line + "\n")
