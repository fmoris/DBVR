import { CharacterConfig, GestureSkillSystem, XRHandsContext } from '../gestures/GestureSkillSystem';
import { Vector3 } from '@babylonjs/core';

// =====================================================================
// UTILS - GSS DATA NORMALIZATION
// =====================================================================

/**
 * Normaliza los datos de gestos. Si vienen en formato 3D (sesiones), los aplasta a 2D (muestras).
 */
function flattenGestures(data: Record<string, any>): Record<string, number[][]> {
    const flattened: Record<string, number[][]> = {};
    for (const [label, samples] of Object.entries(data)) {
        if (Array.isArray(samples) && samples.length > 0) {
            // Si el primer elemento es un array y su primer elemento también es un array, es 3D
            if (Array.isArray(samples[0]) && samples[0].length > 0 && Array.isArray(samples[0][0])) {
                flattened[label] = (samples as number[][][]).flat(1);
            } else {
                flattened[label] = samples as number[][];
            }
        }
    }
    return flattened;
}

// =====================================================================
// CONFIGURACIONES DE PERSONAJES - GSS
// =====================================================================

export const GOKU_CONFIG: CharacterConfig = {
    id: 'goku',
    extractors: {
        'idle': 'wristOnly',
        'kame_charge': 'wristAndFingertips', // Mejorado para precisión
        'genki_charge': 'wristOnly',
        'super_kame_charge': 'wristAndFingertips',
        'ki_blast_ready': 'wristOnly',
        'ki_blast_firing': 'wristAndFingertips', // Fase 2
        'kaioken_ready': 'wristAndFingertips',
        'recharge_ready': 'wristOnly', // Fase 1
        'recharging': 'wristAndFingertips' // Fase 2
    },
    thresholds: {
        'idle': 0.70,
        'kame_charge': 0.75,
        'genki_charge': 0.75,
        'super_kame_charge': 0.80,
        'ki_blast_ready': 0.65,
        'ki_blast_firing': 0.85,
        'kaioken_ready': 0.85,
        'recharge_ready': 0.75,
        'recharging': 0.90
    },
    timing: {
        kamehameha: { minChargeMs: 1250, maxChargeMs: 2500, releaseVelocity: 1.0 },
        genkidama: { minChargeMs: 2500, maxChargeMs: 5000, releaseVelocity: 1.0 },
        super_kamehameha: { minChargeMs: 1500, maxChargeMs: 3000, releaseVelocity: 1.2 },
        kaioken: { minChargeMs: 1000, maxChargeMs: 2000, releaseVelocity: 0.5 },
        kiBlast: { minChargeMs: 1000, maxChargeMs: 1500, quickVelocity: 0.8 },
    },
    gestureIds: [
        'kamehameha_preparation',
        'kamehameha_firing',
        'genkidama_preparation',
        'genkidama_firing',
        'ki_prep',
        'ki_fire',
        'recharge_prep',
        'recharge_active'
    ],
    fsmHandler: function(this: GestureSkillSystem, gesture: string, _confidence: number, ctx: XRHandsContext, now: number) {
        const g = {
            kame_prep:   'kamehameha_preparation',
            kame_fire:   'kamehameha_firing',
            genki_prep:  'genkidama_preparation',
            genki_fire:  'genkidama_firing',
            skame_prep:  'kamehameha_preparation',
            skame_fire:  'kamehameha_firing',
            kaioken:     'kaioken_activation',
            // Usamos las etiquetas con cientos de frames (ki_prep/ki_fire) en lugar de las de 10 frames
            kiblast_prep: 'ki_prep',
            kiblast_fire: 'ki_fire',
            recharge_prep: 'recharge_prep',
            recharge_active: 'recharge_active'
        };

        const t = this.activeCharacter?.timing;
        const gss = this;

        switch (this.currentState) {
            case 'idle': {
                // Guards para evitar falsos positivos
                const isHandsAtHip = gss.lastLocalL.y < 0 && gss.lastLocalR.y < 0;
                const isHandsClose = gss.lastLocalL.length() < 0.4 || gss.lastLocalR.length() < 0.4;
                const handsDistance = Vector3.Distance(gss.lastLocalL, gss.lastLocalR);
                const isHandsTogether = handsDistance < 0.35;

                if (gesture === g.kame_prep && isHandsAtHip && isHandsTogether) {
                    this.setState('kame_charge');
                    this.startCharge('kamehameha', 'both', now);
                } else if (gesture === g.genki_prep) {
                    this.setState('genki_charge');
                    this.startCharge('genkidama', 'both', now);
                } else if (gesture === g.skame_prep && isHandsTogether) {
                    this.setState('super_kame_charge');
                    this.startCharge('super_kamehameha', 'both', now);
                } else if (gesture === g.kiblast_prep && !isHandsTogether) {
                    const activeHand = this.getActiveHand(ctx);
                    const localHand = activeHand === 'left' ? gss.lastLocalL : gss.lastLocalR;
                    // Ki blast is usually shot with the hand raised and somewhat extended forward
                    const isHandRaised = localHand.y > -0.4; // Ligeramente mas relajado
                    
                    if (isHandRaised) {
                        this.lastBlastHand = activeHand;
                        this.setState('ki_blast_ready');
                        this.startCharge('ki_blast', activeHand, now);
                    }
                } else if (gesture === g.recharge_prep && _confidence > 0.85) {
                    // Phase 1: Manos en posición, pero aún no cargando
                    const isHandsLow = gss.lastLocalL.y < -0.2 && gss.lastLocalR.y < -0.2;
                    if (isHandsLow) {
                        this.setState('recharge_ready');
                    }
                }
                break;
            }

            case 'recharge_ready': {
                const isHandsLow = gss.lastLocalL.y < -0.2 && gss.lastLocalR.y < -0.2;
                if (!isHandsLow) {
                    this.setState('idle');
                } else if (gesture === g.recharge_active && _confidence > 0.90) {
                    // Transición a la carga real (Fase 2) - Más estricta para evitar ruido
                    this.setState('recharging');
                }
                break;
            }

            case 'recharging': {
                const isHandsLow = gss.lastLocalL.y < -0.2 && gss.lastLocalR.y < -0.2;
                
                if (!isHandsLow) {
                    this.setState('idle');
                } else if (gesture === g.recharge_prep) {
                    // Volver a posición de espera (Pausar carga)
                    this.setState('recharge_ready');
                } else if (gesture === g.recharge_active) {
                    // Carga activa (Fase 2)
                    this.fireAttack('recharge', 1.0, 'both', false);
                } else {
                    this.setState('idle');
                }
                break;
            }

            case 'kame_charge': {
                const ratio = this.getChargeRatio(t?.kamehameha.maxChargeMs || 2500, now);
                this.onChargeUpdate('kamehameha', ratio, ctx);
                
                if (gesture === g.kame_fire && (now - this.chargeStartTime) >= (t?.kamehameha.minChargeMs || 1000)) {
                    this.fireAttack('kamehameha', 1.0 + ratio * 2.0, 'both');
                } else if (gesture !== g.kame_prep && gesture !== g.kame_fire && gesture !== 'none') {
                    // Si el gesto cambia a algo totalmente distinto, cancelar. 
                    console.log(`[GSS] Carga de KAMEHAMEHA cancelada (Gesto: ${gesture})`);
                    this.setState('idle');
                }
                break;
            }

            case 'genki_charge': {
                const ratio = this.getChargeRatio(t?.genkidama.maxChargeMs || 5000, now);
                this.onChargeUpdate('genkidama', ratio, ctx);

                if (gesture === g.genki_fire && (now - this.chargeStartTime) >= (t?.genkidama.minChargeMs || 2500)) {
                    this.fireAttack('genkidama', 2.0 + ratio * 8.0, 'both');
                } else if (gesture !== g.genki_prep && gesture !== g.genki_fire && gesture !== 'none') {
                    console.log(`[GSS] Carga de GENKIDAMA cancelada (Gesto: ${gesture})`);
                    this.setState('idle');
                }
                break;
            }

            case 'super_kame_charge': {
                const ratio = this.getChargeRatio(t?.super_kamehameha.maxChargeMs || 3000, now);
                this.onChargeUpdate('super_kamehameha', ratio, ctx);

                if (gesture === g.skame_fire && (now - this.chargeStartTime) >= (t?.super_kamehameha.minChargeMs || 1500)) {
                    this.fireAttack('super_kamehameha', 3.0 + ratio * 5.0, 'both');
                } else if (gesture !== g.skame_prep && gesture !== g.skame_fire && gesture !== 'none') {
                    console.log(`[GSS] Carga de SUPER KAMEHAMEHA cancelada (Gesto: ${gesture})`);
                    this.setState('idle');
                }
                break;
            }

            case 'ki_blast_ready':
                // Al detectar el gesto de fuego, empezamos la fase de "mantenimiento" (firing)
                if (gesture === g.kiblast_fire) {
                    this.setState('ki_blast_firing');
                    this.startCharge('ki_blast', this.lastBlastHand || 'right', now);
                } else if (gesture !== g.kiblast_prep && gesture !== 'none') {
                    console.log(`[GSS] Preparación de KI BLAST cancelada (Gesto: ${gesture})`);
                    this.setState('idle');
                }
                break;

            case 'ki_blast_firing': {
                const elapsed = now - this.chargeStartTime;
                const hand = this.lastBlastHand || 'right';
                const tBlast = t?.kiBlast;

                // Mientras mantenga el gesto, actualizamos la carga (solo si sobrepasa el umbral de 1s)
                if (gesture === g.kiblast_fire) {
                    if (elapsed >= (tBlast?.minChargeMs || 1000)) {
                        // El ratio de carga para el efecto visual empieza a contar desde el segundo 1
                        const chargeRatio = Math.min((elapsed - 1000) / ((tBlast?.maxChargeMs || 1500) - 1000), 1.0);
                        this.onChargeUpdate('ki_blast_charged', chargeRatio, ctx);
                    }
                } else {
                    // DISPARO POR LIBERACIÓN (Release on Loss)
                    if (elapsed < (tBlast?.minChargeMs || 1000)) {
                        this.fireAttack('ki_blast_normal', 0.5, hand);
                    } else {
                        const chargeRatio = Math.min((elapsed - 1000) / ((tBlast?.maxChargeMs || 1500) - 1000), 1.0);
                        this.fireAttack('ki_blast_charged', 1.0 + chargeRatio * 1.5, hand);
                    }
                    // El auto-idle de fireAttack nos devuelve a base
                }
                break;
            }
        }
    }
};

// Placeholder para Vegeta
export const VEGETA_CONFIG: CharacterConfig = {
    id: 'vegeta',
    gestureIds: ['ki_prep', 'ki_fire', 'recharge_prep', 'recharge_active'], // Sincronizado
    extractors: { 'idle': 'wristOnly' },
    thresholds: { 'idle': 0.70 },
    fsmHandler: function(this: GestureSkillSystem, _gesture: string, _confidence: number, _ctx: XRHandsContext, _now: number) {
        // Lógica similar a Goku pero con Galick Gun, etc.
    }
};
