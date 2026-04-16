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
        'kame_charge': 'wristOnly',
        'genki_charge': 'wristOnly',
        'super_kame_charge': 'wristAndFingertips',
        'ki_blast_ready': 'wristOnly',
        'kaioken_ready': 'wristAndFingertips',
        'recharging': 'wristAndFingertips'
    },
    thresholds: {
        'idle': 0.70,
        'kame_charge': 0.75,
        'genki_charge': 0.75,
        'super_kame_charge': 0.80,
        'ki_blast_ready': 0.65,
        'kaioken_ready': 0.85,
        'recharging': 0.85
    },
    timing: {
        kamehameha: { minChargeMs: 1250, maxChargeMs: 2500, releaseVelocity: 1.0 },
        genkidama: { minChargeMs: 2500, maxChargeMs: 5000, releaseVelocity: 1.0 },
        super_kamehameha: { minChargeMs: 1500, maxChargeMs: 3000, releaseVelocity: 1.2 },
        kaioken: { minChargeMs: 1000, maxChargeMs: 2000, releaseVelocity: 0.5 },
        kiBlast: { quickThresholdMs: 200, chargeStartMs: 800, quickVelocity: 0.8 },
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
                    // Recharge: Manos en mitad inferior del torso (y < -0.2)
                    const isHandsLow = gss.lastLocalL.y < -0.2 && gss.lastLocalR.y < -0.2;
                    if (isHandsLow) {
                        this.setState('recharging');
                    }
                }
                break;
            }

            case 'recharging': {
                const isHandsLow = gss.lastLocalL.y < -0.2 && gss.lastLocalR.y < -0.2;
                // Aceptamos cualquiera de las dos fases de recharge para mantener el estado
                const isRecharging = gesture === g.recharge_prep || gesture === g.recharge_active;
                
                if (!isRecharging || !isHandsLow) {
                    this.setState('idle');
                } else {
                    this.fireAttack('recharge', 1.0, 'both');
                }
                break;
            }

            case 'kame_charge': {
                const ratio = this.getChargeRatio(t?.kamehameha.maxChargeMs || 2500, now);
                this.onChargeUpdate('kamehameha', ratio);
                
                if (gesture === g.kame_fire && (now - this.chargeStartTime) >= (t?.kamehameha.minChargeMs || 1000)) {
                    this.fireAttack('kamehameha', 1.0 + ratio * 2.0, 'both');
                    this.setState('idle');
                } else if (gesture !== g.kame_prep && gesture !== g.kame_fire && gesture !== 'none') {
                    // Si el gesto cambia a algo totalmente distinto, cancelar. 
                    console.log(`[GSS] Carga de KAMEHAMEHA cancelada (Gesto: ${gesture})`);
                    this.setState('idle');
                }
                break;
            }

            case 'genki_charge': {
                const ratio = this.getChargeRatio(t?.genkidama.maxChargeMs || 5000, now);
                this.onChargeUpdate('genkidama', ratio);

                if (gesture === g.genki_fire && (now - this.chargeStartTime) >= (t?.genkidama.minChargeMs || 2500)) {
                    this.fireAttack('genkidama', 2.0 + ratio * 8.0, 'both');
                    this.setState('idle');
                } else if (gesture !== g.genki_prep && gesture !== g.genki_fire && gesture !== 'none') {
                    console.log(`[GSS] Carga de GENKIDAMA cancelada (Gesto: ${gesture})`);
                    this.setState('idle');
                }
                break;
            }

            case 'super_kame_charge': {
                const ratio = this.getChargeRatio(t?.super_kamehameha.maxChargeMs || 3000, now);
                this.onChargeUpdate('super_kamehameha', ratio);

                if (gesture === g.skame_fire && (now - this.chargeStartTime) >= (t?.super_kamehameha.minChargeMs || 1500)) {
                    this.fireAttack('super_kamehameha', 3.0 + ratio * 5.0, 'both');
                    this.setState('idle');
                } else if (gesture !== g.skame_prep && gesture !== g.skame_fire && gesture !== 'none') {
                    console.log(`[GSS] Carga de SUPER KAMEHAMEHA cancelada (Gesto: ${gesture})`);
                    this.setState('idle');
                }
                break;
            }

            case 'ki_blast_ready':
                if (gesture === g.kiblast_fire) {
                    const elapsed = now - this.chargeStartTime;
                    const hand = this.lastBlastHand || 'right';
                    if (elapsed < (t?.kiBlast.quickThresholdMs || 200)) {
                        this.fireAttack('ki_blast_quick', 0.5, hand);
                    } else {
                        const ratio = this.getChargeRatio(t?.kiBlast.chargeStartMs || 800, now);
                        this.fireAttack('ki_blast_charged', 1.0 + ratio, hand);
                    }
                    this.setState('idle');
                } else if (gesture !== g.kiblast_prep && gesture !== g.kiblast_fire && gesture !== 'none') {
                    console.log(`[GSS] Preparación de KI BLAST cancelada (Gesto: ${gesture})`);
                    this.setState('idle');
                }
                break;
        }
    }
};

// Placeholder para Vegeta
export const VEGETA_CONFIG: CharacterConfig = {
    id: 'vegeta',
    gestureIds: ['ki_prep', 'ki_fire', 'recharge'], // Vegeta comparte gestos con Goku
    extractors: { 'idle': 'wristOnly' },
    thresholds: { 'idle': 0.70 },
    fsmHandler: function(this: GestureSkillSystem, _gesture: string, _confidence: number, _ctx: XRHandsContext, _now: number) {
        // Lógica similar a Goku pero con Galick Gun, etc.
    }
};
