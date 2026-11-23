class_name PowerData
extends Resource

@export var power_name: String = ""
@export var gesture_trigger: String = "" # Identificador en el GesturePhaseTree (KAMEHAMEHA, GENKIDAMA, KI_BLAST)
@export var ki_cost: float = 10.0
@export var base_damage_np: float = 1000.0 # Daño infligido al NP del rival
@export var projectile_speed: float = 30.0
@export var energy_color: Color = Color(1, 1, 1, 1)

# Lógica de Desbloqueo Dinámico, Restricción y Finisher
@export var unlock_requirement_transformation: String = "" # En blanco = disponible en base por defecto
@export var forbidden_transformations: Array[String] = [] # Fases donde no se puede usar (ej: Genkidama prohibida en SSJ)
@export var is_finisher: bool = false # Si es true, finaliza la partida al impactar en Zenkai

@export_group("Zenkai Explosión, Audio y Animación")
@export var explosion_tier: int = 2
@export var charge_action_id: String = ""
@export var fire_action_id: String = ""
@export var impact_action_id: String = "common.ki_blast_impact"
@export var anim_clip_prefix: String = "hissatsu1"
