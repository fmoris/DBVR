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
    "recharge_prep": {
        left: new Vector3(-0.2, 0.2, 0.2),
        right: new Vector3(0.2, 0.2, 0.2)
    },
    "recharge_active": {
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
    constructor() { }

    public getPose(poseName: string): PoseReference {
        const base = DEFAULT_POSES[poseName] || { left: new Vector3(-0.2, 1.2, 0.3), right: new Vector3(0.2, 1.2, 0.3) };
        return { ...base };
    }

    public setOverride(_poseName: string, _ref: PoseReference) {
        // No-op: Poses fijas ahora vienen de DEFAULT_POSES
        console.log(`[PoseRef] Override ignorado.`);
    }

    public reset() { }

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
