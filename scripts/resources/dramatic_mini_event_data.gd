class_name DramaticMiniEventData
extends Resource

## Recurso data-driven que define una Mini-Escena Dramática interactiva (general o exclusiva de personaje).

@export var event_id: String = ""
@export var display_name: String = ""
@export var instruction_text: String = ""
## "" = General (todos), "goku", "vegeta", etc.
@export var character_filter: String = ""
## "low_ki_or_even", "after_melee_or_behind", "threshold_50_plus", "base_or_behind", "intense_or_furia", "pressure_or_furia", "dominating_or_ssj"
@export var condition_type: String = "any"
## "shake_pump", "orb_tap", "hold_expand", "sky_absorb", "rhythm_pulse", "rapid_punch", "aim_targets"
@export var minigame_type: String = "shake_pump"
@export var target_count: int = 6
@export var duration_sec: float = 3.5
@export var is_permanent_bonus: bool = false
@export var bonus_duration_sec: float = 18.0
@export var bonus_label: String = ""
@export var bonus_effect_text: String = ""
@export var bonus_color: Color = Color(0.2, 0.9, 1.0)
## Claves admitidas: instant_ki, instant_bp, passive_ki_mult, blast_cost_mult, blast_charge_speed_mult,
## bullet_time_mult, bp_gain_mult, transform_drain_mult, ki_recharge_mult, super_charge_speed_mult,
## damage_mult, flight_speed_mult, super_damage_mult, furia_threshold
@export var bonus_mods: Dictionary = {}
@export var weight: float = 1.0
