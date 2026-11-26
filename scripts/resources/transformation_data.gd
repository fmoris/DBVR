class_name TransformationData
extends Resource

@export var form_name: String = "" # Nombre de la transformación (ej: SSJ, SSJ2, Super Vegeta, SSB, Ultra Instinto)
@export var tier_level: int = 1 # Tier canónico 1..4 del sistema equilibrado
@export var np_multiplier: float = 2.0 # Multiplica el NP máximo y aumenta el daño
@export var ki_drain_per_sec: float = 1.0 # Costo por segundo para mantener la transformación
@export var ki_max_bonus: float = 0.0 # Aumento adicional al tope máximo de Ki en esta forma
@export var ki_transform_restore: float = 25.0 # Bono instantáneo de Ki al completar la transformación
@export var aura_color: Color = Color(1, 0.8, 0, 1) # Color del aura de energía del personaje

@export_group("Zenkai VFX, Iluminación, Audio y Animación")
@export var aura_vfx_path: String = ""
@export var has_bio_lightning: bool = false
@export var light_energy: float = 2.5
@export var light_range: float = 4.5
@export var aura_loop_action_id: String = "common.ki_charge_phase2"
@export var anim_library_path: String = ""

@export_group("Modelos Opcionales por Transformación")
@export_file("*.glb") var body_model_path: String = ""
@export_file("*.glb") var hands_model_path: String = ""

@export_group("Selector e Info API")
@export var api_id: int = 0
@export var canonical_ki_text: String = ""
@export_file("*.webp", "*.png") var portrait_image_path: String = ""
@export var api_image_url: String = ""
