import { CharacterConfig, GestureSkillSystem, XRHandsContext } from './GestureSkillSystem';
import kameGestures from '../models/goku/gestures/kamehameha.json';
import genkiGestures from '../models/goku/gestures/genkidama.json';
import kiBlastGestures from '../models/goku/gestures/ki_blast.json';
import kaiokenGestures from '../models/goku/gestures/kaioken.json';
import kiChargeGestures from '../models/goku/gestures/ki_charge.json';

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
        'recharging': 'wristOnly'
    },
    thresholds: {
        'idle': 0.70,
        'kame_charge': 0.75,
        'genki_charge': 0.75,
        'super_kame_charge': 0.80,
        'ki_blast_ready': 0.65,
        'kaioken_ready': 0.85,
        'recharging': 0.70
    },
    timing: {
        kamehameha: { minChargeMs: 1250, maxChargeMs: 2500, releaseVelocity: 1.0 },
        genkidama: { minChargeMs: 2500, maxChargeMs: 5000, releaseVelocity: 1.0 },
        super_kamehameha: { minChargeMs: 1500, maxChargeMs: 3000, releaseVelocity: 1.2 },
        kaioken: { minChargeMs: 1000, maxChargeMs: 2000, releaseVelocity: 0.5 },
        kiBlast: { quickThresholdMs: 200, chargeStartMs: 800, quickVelocity: 0.8 },
    },
    defaultData: {
        ...flattenGestures(kameGestures),
        ...flattenGestures(genkiGestures),
        ...flattenGestures(kiBlastGestures),
        ...flattenGestures(kaiokenGestures),
        ...flattenGestures(kiChargeGestures)
    },
    fsmHandler: function(this: GestureSkillSystem, gesture: string, _confidence: number, ctx: XRHandsContext, now: number) {
        const g = {
            kame_prep:   'kamehameha_preparation',
            kame_fire:   'kamehameha_firing',
            genki_prep:  'genkidama_preparation',
            genki_fire:  'genkidama_firing',
            skame_prep:  'kamehameha_preparation', // Fallback a base para Super Kame
            skame_fire:  'kamehameha_firing',
            kaioken:     'kaioken_activation',
            kiblast_prep: 'ki_blast_preparation',
            kiblast_fire: 'ki_blast_firing',
            recharge:    'ki_charge'
        };

        const t = this.activeCharacter?.timing;

        switch (this.currentState) {
            case 'idle':
                if (gesture === g.kame_prep) {
                    this.setState('kame_charge');
                    this.startCharge('kamehameha', 'both', now);
                } else if (gesture === g.genki_prep) {
                    this.setState('genki_charge');
                    this.startCharge('genkidama', 'both', now);
                } else if (gesture === g.skame_prep) {
                    this.setState('super_kame_charge');
                    this.startCharge('super_kamehameha', 'both', now);
                } else if (gesture === g.kaioken) {
                    this.fireAttack('kaioken', 2.0, 'both');
                    this.setState('idle');
                } else if (gesture === g.kiblast_prep) {
                    this.setState('ki_blast_ready');
                    this.startCharge('ki_blast', this.getActiveHand(ctx), now);
                } else if (gesture === g.recharge) {
                    this.setState('recharging');
                }
                break;

            case 'recharging':
                if (gesture !== g.recharge) {
                    this.setState('idle');
                } else {
                    this.fireAttack('recharge', 0, 'both');
                }
                break;

            case 'kame_charge': {
                const ratio = this.getChargeRatio(t?.kamehameha.maxChargeMs || 2500, now);
                this.onChargeUpdate('kamehameha', ratio);
                
                if (gesture === g.kame_fire && (now - this.chargeStartTime) >= (t?.kamehameha.minChargeMs || 1000)) {
                    this.fireAttack('kamehameha', 1.0 + ratio * 2.0, 'both');
                    this.setState('idle');
                } else if (gesture !== g.kame_prep && gesture !== g.kame_fire) {
                    // Si el gesto cambia a cualquier otro que no sea el de carga o disparo, cancelar
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
                } else if (gesture !== g.genki_prep && gesture !== g.genki_fire) {
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
                } else if (gesture !== g.skame_prep && gesture !== g.skame_fire) {
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
                } else if (gesture !== g.kiblast_prep && gesture !== g.kiblast_fire) {
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
    extractors: { 'idle': 'wristOnly' },
    thresholds: { 'idle': 0.70 },
    fsmHandler: function(this: GestureSkillSystem, _gesture: string, _confidence: number, _ctx: XRHandsContext, _now: number) {
        // Lógica similar a Goku pero con Galick Gun, etc.
    }
};
