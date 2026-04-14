import { Vector3, Quaternion } from "@babylonjs/core";

export interface PoseReference {
    left: Vector3;
    right: Vector3;
    leftRot?: Quaternion;
    rightRot?: Quaternion;
    leftClosed?: boolean;
    rightClosed?: boolean;
}

const DEFAULT_CHEST = new Vector3(0, 1.4, 0.2);

export const DEFAULT_POSES: Record<string, PoseReference> = {
    "hands_clasped_at_waist": {
        left: new Vector3(0.25, -0.3, -0.1),
        right: new Vector3(0.3, -0.3, -0.1)
    },
    "palms_forward_push": {
        left: new Vector3(-0.15, 0.1, 0.6),
        right: new Vector3(0.15, 0.1, 0.6)
    },
    "palms_forward_together": {
        left: new Vector3(-0.05, 0.1, 0.6),
        right: new Vector3(0.05, 0.1, 0.6)
    },
    "arms_extended_horizontally": {
        left: new Vector3(-0.6, 0.1, 0),
        right: new Vector3(0.6, 0.1, 0)
    },
    "arms_raised_to_sky": {
        left: new Vector3(-0.2, 0.6, 0.2),
        right: new Vector3(0.2, 0.6, 0.2)
    },
    "hands_left_shoulder_crossed": {
        left: new Vector3(-0.2, 0.2, -0.1),
        right: new Vector3(-0.1, 0.2, -0.1)
    },
    "ki_prep": {
        left: new Vector3(-0.2, -0.2, 0),
        right: new Vector3(0.2, 0.1, 0.2)
    },
    "ki_fire": {
        left: new Vector3(-0.2, -0.2, 0),
        right: new Vector3(0.1, 0.1, 0.5)
    },
    "ki_charge_prep": {
        left: new Vector3(-0.2, 0.0, 0.1),
        right: new Vector3(0.2, -0.2, 0)
    },
    "ki_charge_fire": {
        left: new Vector3(-0.1, 0.0, 0.5),
        right: new Vector3(0.2, -0.2, 0)
    },
    "recharge_p1": {
        left: new Vector3(-0.2, 0.2, 0.2),
        right: new Vector3(0.2, 0.2, 0.2)
    },
    "recharge_p2": {
        left: new Vector3(-0.4, 0.1, 0.1),
        right: new Vector3(0.4, 0.1, 0.1)
    },
    "palms_forward_push_wide": {
        left: new Vector3(-0.3, 0.1, 0.5),
        right: new Vector3(0.3, 0.1, 0.5)
    },
    "arms_crossed_chest": {
        left: new Vector3(0.15, 0.1, 0.2),
        right: new Vector3(-0.15, 0.1, 0.2)
    },
    "kamehameha_preparation": {
        left: new Vector3(0.25, -0.3, -0.1),
        right: new Vector3(0.3, -0.3, -0.1)
    },
    "kamehameha_firing": {
        left: new Vector3(-0.2, 0.1, 0.6),
        right: new Vector3(0.2, 0.1, 0.6)
    },
    "genkidama_preparation": {
        left: new Vector3(-0.2, 0.6, 0.2),
        right: new Vector3(0.2, 0.6, 0.2)
    },
    "genkidama_firing": {
        left: new Vector3(-0.15, 0.1, 0.6),
        right: new Vector3(0.15, 0.1, 0.6)
    }
};

class PoseReferencesService {
    private overrides: Record<string, PoseReference> = {};

    constructor() {
        this.load();
    }

    private load() {
        const saved = localStorage.getItem('vr_pose_overrides_v2');
        if (saved) {
            try {
                const parsed = JSON.parse(saved);
                // Convert simple objects back to Vector3/Quaternion
                for (const key of Object.keys(parsed)) {
                    const item = parsed[key];
                    if (!item || !item.left || !item.right) continue;
                    
                    this.overrides[key] = {
                        left: Vector3.FromArray(item.left),
                        right: Vector3.FromArray(item.right),
                        leftRot: (item.leftRot && Array.isArray(item.leftRot)) ? Quaternion.FromArray(item.leftRot) : undefined,
                        rightRot: (item.rightRot && Array.isArray(item.rightRot)) ? Quaternion.FromArray(item.rightRot) : undefined,
                        leftClosed: !!item.leftClosed,
                        rightClosed: !!item.rightClosed
                    };
                }
            } catch (e) {
                console.warn("[PoseRef] Error parsing overrides:", e);
            }
        }
    }

    public save() {
        const toSave: Record<string, any> = {};
        for (const key of Object.keys(this.overrides)) {
            const item = this.overrides[key];
            toSave[key] = {
                left: item.left.asArray(),
                right: item.right.asArray(),
                leftRot: item.leftRot?.asArray(),
                rightRot: item.rightRot?.asArray(),
                leftClosed: item.leftClosed,
                rightClosed: item.rightClosed
            };
        }
        localStorage.setItem('vr_pose_overrides_v2', JSON.stringify(toSave));
    }

    public getPose(poseName: string): PoseReference {
        const base = DEFAULT_POSES[poseName] || { left: new Vector3(-0.2, 1.2, 0.3), right: new Vector3(0.2, 1.2, 0.3) };
        const override = this.overrides[poseName];

        if (!override) return { ...base };

        // Combinar base con override (permitir gaps parciales si fuera el caso)
        return {
            left: override.left.clone(),
            right: override.right.clone(),
            leftRot: override.leftRot?.clone(),
            rightRot: override.rightRot?.clone(),
            leftClosed: override.leftClosed,
            rightClosed: override.rightClosed
        };
    }

    public setOverride(poseName: string, ref: PoseReference) {
        this.overrides[poseName] = {
            left: ref.left.clone(),
            right: ref.right.clone(),
            leftRot: ref.leftRot?.clone(),
            rightRot: ref.rightRot?.clone(),
            leftClosed: ref.leftClosed,
            rightClosed: ref.rightClosed
        };
        this.save();
    }

    public reset() {
        this.overrides = {};
        localStorage.removeItem('vr_pose_overrides_v2');
    }

    /**
     * Retorna la pose en espacio MUNDO (relativa al pecho por defecto pero posicionada)
     */
    public getWorldPose(poseName: string): PoseReference {
        const local = this.getPose(poseName);
        return {
            left: DEFAULT_CHEST.add(local.left),
            right: DEFAULT_CHEST.add(local.right),
            leftRot: local.leftRot,
            rightRot: local.rightRot,
            leftClosed: local.leftClosed,
            rightClosed: local.rightClosed
        };
    }
}

export const PoseManager = new PoseReferencesService();

// Mantener compatibilidad con exports viejos para no romper el simulador de golpe
export const POSE_REFERENCES = DEFAULT_POSES;
export function getReferencePose(poseName: string) {
    return PoseManager.getWorldPose(poseName);
}
