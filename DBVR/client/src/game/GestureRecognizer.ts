/**
 * GestureRecognizer v2
 * Detecta gestos de manos usando los nombres de joints de WebXR Hand Tracking API
 * Calibrado para Meta Quest 3 con referenceSpace "local-floor"
 *
 * Nombres de joints WebXR estándar (Babylon los expone como strings):
 *   wrist, thumb-tip, index-finger-tip, middle-finger-tip,
 *   ring-finger-tip, little-finger-tip, index-finger-metacarpal,
 *   middle-finger-metacarpal, ring-finger-metacarpal, little-finger-metacarpal
 */

export enum GestureType {
  IDLE        = "IDLE",
  CHARGING    = "CHARGING",
  ATTACKING   = "ATTACKING",
  BLOCKING    = "BLOCKING",
  PARRYING    = "PARRYING",
  RECHARGING  = "RECHARGING",
  RECHARGE_PREP = "RECHARGE_PREP",
  KAMEHAMEHA  = "KAMEHAMEHA",
  KAMEHAMEHA_PREP = "KAMEHAMEHA_PREP",
  KI_BLAST_L  = "KI_BLAST_L",
  KI_BLAST_R  = "KI_BLAST_R",
  CHARGED_KI_BLAST_L = "CHARGED_KI_BLAST_L",
  CHARGED_KI_BLAST_R = "CHARGED_KI_BLAST_R",
}

export interface HandJoints {
  wrist:      { x: number; y: number; z: number };
  indexTip:   { x: number; y: number; z: number };
  middleTip:  { x: number; y: number; z: number };
  ringTip:    { x: number; y: number; z: number };
  littleTip:  { x: number; y: number; z: number };
  thumbTip:   { x: number; y: number; z: number };
}

// Nombres de joints en la API WebXR Hand Tracking (estándar W3C)
const JOINT_NAMES = {
  wrist:     "wrist",
  thumbTip:  "thumb-tip",
  indexTip:  "index-finger-tip",
  middleTip: "middle-finger-tip",
  ringTip:   "ring-finger-tip",
  littleTip: "little-finger-tip",
} as const;

/**
 * Extrae los joints de un WebXRHand de Babylon 6.
 *
 * Babylon 6 expone los joints de tres formas posibles según la versión:
 *   1. hand.getJointMesh(jointName) → AbstractMesh con .position (Vector3)
 *   2. hand._jointMeshes como Map<string, AbstractMesh>
 *   3. hand.xrController.hand (XRHand nativo) + referenceSpace para getJointPose
 *
 * El método más confiable es getJointMesh, que devuelve el mesh del joint
 * cuya posición se actualiza cada frame por Babylon.
 */
export function extractHandJoints(hand: any): HandJoints | null {
  if (!hand) return null;

  const get = (name: string, fallbackIdx: number): { x: number; y: number; z: number } => {
    try {
      let pos: any = null;

      // Método 1: getJointMesh (Babylon 6 WebXRHandTracking)
      if (typeof hand.getJointMesh === "function") {
        const mesh = hand.getJointMesh(name);
        if (mesh) {
           mesh.computeWorldMatrix(true);
           pos = mesh.getAbsolutePosition();
        }
      }

      // Método 2: _jointMeshes como Map<string, AbstractMesh>
      if (!pos && hand._jointMeshes instanceof Map) {
        const mesh = hand._jointMeshes.get(name);
        if (mesh) {
           mesh.computeWorldMatrix(true);
           pos = mesh.getAbsolutePosition();
        }
      }

      // Método 3: jointMeshes como array indexado (Babylon < 6.x)
      if (!pos && Array.isArray(hand.jointMeshes)) {
        const mesh = hand.jointMeshes[fallbackIdx];
        if (mesh) {
           mesh.computeWorldMatrix(true);
           pos = mesh.getAbsolutePosition();
        }
      }

      // Método 4: joints como objeto plano con nombres
      if (!pos && hand.joints && typeof hand.joints === "object") {
        const j = hand.joints[name] ?? hand.joints[fallbackIdx];
        if (j) {
           if (typeof j.getAbsolutePosition === "function") pos = j.getAbsolutePosition();
           else if (j.position) pos = j.position;
           else if (j.x !== undefined) pos = j;
        }
      }

      if (pos) return { x: pos.x ?? 0, y: pos.y ?? 0, z: pos.z ?? 0 };
    } catch (_) { /* silencioso */ }
    return { x: 0, y: 0, z: 0 };
  };

  const joints: HandJoints = {
    wrist:     get(JOINT_NAMES.wrist,     0),
    thumbTip:  get(JOINT_NAMES.thumbTip,  4),
    indexTip:  get(JOINT_NAMES.indexTip,  8),
    middleTip: get(JOINT_NAMES.middleTip, 12),
    ringTip:   get(JOINT_NAMES.ringTip,   16),
    littleTip: get(JOINT_NAMES.littleTip, 20),
  };

  // Validar que al menos el wrist tiene datos reales (no todos ceros)
  const hasData =
    joints.wrist.x !== 0 || joints.wrist.y !== 0 || joints.wrist.z !== 0 ||
    joints.indexTip.x !== 0 || joints.indexTip.y !== 0;
  if (!hasData) return null;

  return joints;
}

export enum StaticPose {
  UNKNOWN = "UNKNOWN",
  FISTS_HIGH = "FISTS_HIGH",
  FISTS_SIDES = "FISTS_SIDES",
  PALMS_HIP_RIGHT = "PALMS_HIP_RIGHT",
  PALMS_FORWARD_STACKED = "PALMS_FORWARD_STACKED",
  ARMS_CROSSED = "ARMS_CROSSED",
  FISTS_CHEST = "FISTS_CHEST",
  PALM_STOP_L = "PALM_STOP_L",
  PALM_STOP_R = "PALM_STOP_R",
  PALM_THRUST_L = "PALM_THRUST_L",
  PALM_THRUST_R = "PALM_THRUST_R",
  FIST_FORWARD_L = "FIST_FORWARD_L",
  FIST_FORWARD_R = "FIST_FORWARD_R",
  // Nuevas poses para ataques especiales
  HANDS_LEFT_SHOULDER = "HANDS_LEFT_SHOULDER",
  ARMS_HORIZONTAL = "ARMS_HORIZONTAL",
  PALMS_TOGETHER = "PALMS_TOGETHER",
  ARMS_UP = "ARMS_UP",
  ARMS_THROW = "ARMS_THROW",
  ARMS_CROSSED_CHEST = "ARMS_CROSSED_CHEST",
  ARMS_SPREAD = "ARMS_SPREAD",
  PALM_AIM = "PALM_AIM",
  FIST_CLENCH = "FIST_CLENCH"
}

// Mapeo de strings de powers.json a StaticPose
const POSE_STRING_MAP: Record<string, StaticPose> = {
  "hands_clasped_at_waist":         StaticPose.PALMS_HIP_RIGHT,
  "palms_forward_push":            StaticPose.PALMS_FORWARD_STACKED,
  "hands_left_shoulder_crossed":   StaticPose.HANDS_LEFT_SHOULDER,
  "arms_extended_horizontally":    StaticPose.ARMS_HORIZONTAL,
  "palms_forward_together":        StaticPose.PALMS_TOGETHER,
  "arms_raised_to_sky":            StaticPose.ARMS_UP,
  "arms_throw_forward":             StaticPose.ARMS_THROW,
  "arms_crossed_chest_look_up":    StaticPose.ARMS_CROSSED_CHEST,
  "arms_spread_wide_roar":         StaticPose.ARMS_SPREAD,
  "palm_forward_aim":              StaticPose.PALM_AIM,
  "clench_fist":                   StaticPose.FIST_CLENCH,
  "fist_forward":                  StaticPose.FIST_FORWARD_R,
  "palm_stop":                     StaticPose.PALM_STOP_R
};

const Combos: Record<string, StaticPose[]> = {
  "RECHARGING":   [StaticPose.FISTS_HIGH,       StaticPose.FISTS_SIDES],
  "KAMEHAMEHA":   [StaticPose.PALMS_HIP_RIGHT,  StaticPose.PALMS_FORWARD_STACKED],
  "KI_BLAST_L":   [StaticPose.PALM_STOP_L,      StaticPose.PALM_THRUST_L],
  "KI_BLAST_R":   [StaticPose.PALM_STOP_R,      StaticPose.PALM_THRUST_R],
  "CHARGED_KI_BLAST_L": [StaticPose.FIST_FORWARD_L, StaticPose.PALM_STOP_L],
  "CHARGED_KI_BLAST_R": [StaticPose.FIST_FORWARD_R, StaticPose.PALM_STOP_R]
};

import powersConfig from "../models/powers.json";

export class GestureRecognizer {
  private leftHandJoints:  HandJoints | null = null;
  private rightHandJoints: HandJoints | null = null;
  private currentGesture: GestureType = GestureType.IDLE;
  private frameCount = 0;

  // Estado del Motor de Combos
  private activeCombo: string | null = null;
  private comboStep: number = 0;
  private lastPoseTime: number = 0;
  private lastHandDetectionTime: number = Date.now();
  private consecutiveWrongPoseCount: number = 0;
  private comboStartTime: number = 0;
  private lastSpecialEndTime: number = 0;
  private leftHandStartPos: { x: number; y: number; z: number } | null = null;
  private rightHandStartPos: { x: number; y: number; z: number } | null = null;
  private dynamicCombos: Record<string, StaticPose[]> = { ...Combos };
  private allowedPowers: string[] = [];

  private gestureCooldownMs: Record<GestureType | string, number> = {
    [GestureType.IDLE]:       0,
    [GestureType.ATTACKING]:  600,
    [GestureType.CHARGING]:   200,
    [GestureType.BLOCKING]:   150,
    [GestureType.PARRYING]:   400,
    [GestureType.RECHARGING]: 200,
    [GestureType.RECHARGE_PREP]: 0,
    "KAMEHAMEHA": 1000,
    "KI_BLAST_L": 150,
    "KI_BLAST_R": 150
  };
  private lastGestureTime = 0;

  // Calculadoras de Velocidad
  private leftVelocityZ: number = 0;
  private rightVelocityZ: number = 0;

  constructor(_scene?: any) {}

  updateHandJoints(hand: "left" | "right", joints: HandJoints): void {
    if (hand === "left") {
       if (this.leftHandJoints) {
           this.leftVelocityZ = joints.wrist.z - this.leftHandJoints.wrist.z;
       }
       this.leftHandJoints = joints;
    } else {
       if (this.rightHandJoints) {
           this.rightVelocityZ = joints.wrist.z - this.rightHandJoints.wrist.z;
       }
       this.rightHandJoints = joints;
    }
    this.frameCount++;
    if (this.frameCount % 2 === 0) this.recognizeGesture();
  }

  private evaluateValidPoses(L: HandJoints, R: HandJoints): StaticPose[] {
    const poses: StaticPose[] = [];
    const isFistL = this.isFist(L);
    const isFistR = this.isFist(R);

    const isOpenL = !isFistL && this.dist3(L.indexTip, L.wrist) > 0.14 && L.indexTip.y > L.wrist.y + 0.10;
    const isOpenR = !isFistR && this.dist3(R.indexTip, R.wrist) > 0.14 && R.indexTip.y > R.wrist.y + 0.10;

    // 1. RECHARGE_P1
    if (isFistL && isFistR && L.wrist.y > 1.0 && R.wrist.y > 1.0) {
       poses.push(StaticPose.FISTS_HIGH);
    }

    // 2. RECHARGE_P2: Subir límite superior a 1.50m por ergonomía
    const xDist = Math.abs(L.wrist.x - R.wrist.x);
    if (isFistL && isFistR && xDist >= 0.30 && L.wrist.y <= 1.50 && R.wrist.y <= 1.50) {
       poses.push(StaticPose.FISTS_SIDES);
    }

    // 3. KAMEHAMEHA_P1
    if (!isFistL && !isFistR && L.wrist.x > 0.05 && R.wrist.x > 0.05 && L.wrist.y < 1.3 && R.wrist.y < 1.3) {
       poses.push(StaticPose.PALMS_HIP_RIGHT);
    }

    // 4. KAMEHAMEHA_P2: Más tolerante
    const rightAboveLeft = R.wrist.y > L.wrist.y;
    const yDist = Math.abs(R.wrist.y - L.wrist.y);
    const closeXZ = Math.abs(L.wrist.x - R.wrist.x) < 0.35 && Math.abs(L.wrist.z - R.wrist.z) < 0.35;
    const forwardPush = L.wrist.z > 0.3 && R.wrist.z > 0.3; 
    if (!isFistL && !isFistR && rightAboveLeft && yDist > 0.02 && closeXZ && forwardPush) {
       poses.push(StaticPose.PALMS_FORWARD_STACKED);
    }

    // 5. THRUSTS (Ataques rápidos)
    // Se requiere aceleración > 0.02 y un desplazamiento mínimo de 15cm desde el inicio
    if (isOpenL && this.leftVelocityZ > 0.02) {
        const start = this.leftHandStartPos;
        if (start && this.dist3(L.wrist, start) > 0.15) {
            poses.push(StaticPose.PALM_THRUST_L);
        }
    }
    if (isOpenR && this.rightVelocityZ > 0.02) {
        const start = this.rightHandStartPos;
        if (start && this.dist3(R.wrist, start) > 0.15) {
            poses.push(StaticPose.PALM_THRUST_R);
        }
    }

    // 6. FIST FORWARD (Carga de Ki Blast)
    // Brazo extendido hacia adelante
    if (isFistL && L.wrist.z > 0.35) poses.push(StaticPose.FIST_FORWARD_L);
    if (isFistR && R.wrist.z > 0.35) poses.push(StaticPose.FIST_FORWARD_R);

    // 7. STOPS (Poses estáticas de preparación)
    if (isOpenL) poses.push(StaticPose.PALM_STOP_L);
    if (isOpenR) poses.push(StaticPose.PALM_STOP_R);

    // 8. NUEVAS POSES ESPECIALES
    // Final Flash Prep: brazos extendidos horizontalmente
    if (L.wrist.y > 1.2 && R.wrist.y > 1.2 && Math.abs(L.wrist.x) > 0.4 && Math.abs(R.wrist.x) > 0.4) {
      poses.push(StaticPose.ARMS_HORIZONTAL);
    }
    // Final Flash Fire: manos juntas frente al pecho
    if (this.dist3(L.wrist, R.wrist) < 0.15 && L.wrist.z > 0.3) {
      poses.push(StaticPose.PALMS_TOGETHER);
    }
    // Galick Gun: manos cruzadas en el hombro izquierdo
    if (L.wrist.x > 0.1 && R.wrist.x > 0.1 && L.wrist.y > 1.3 && R.wrist.y > 1.3) {
      poses.push(StaticPose.HANDS_LEFT_SHOULDER);
    }
    // Genkidama Prep: brazos al cielo (1.6m más ergonómico)
    if (L.wrist.y > 1.6 && R.wrist.y > 1.6) {
      poses.push(StaticPose.ARMS_UP);
    }
    // Genkidama Fire: brazos lanzados adelante
    if (L.wrist.y < 1.4 && R.wrist.y < 1.4 && L.wrist.z > 0.4 && R.wrist.z > 0.4) {
      poses.push(StaticPose.ARMS_THROW);
    }
    // Final Explosion Prep: brazos cruzados en el pecho
    if (Math.abs(L.wrist.x - R.wrist.x) < 0.2 && L.wrist.y > 1.2 && L.wrist.y < 1.6) {
       poses.push(StaticPose.ARMS_CROSSED_CHEST);
    }
    // Hakai Prep: apuntar mano palma abierta
    if (isOpenR && R.wrist.z > 0.5) {
      poses.push(StaticPose.PALM_AIM);
    }
    // Hakai Fire: cerrar puño
    if (isFistR && R.wrist.z > 0.5) {
      poses.push(StaticPose.FIST_CLENCH);
    }

    return poses;
  }

  private recognizeGesture(): void {
    const now = Date.now();
    const L = this.leftHandJoints;
    const R = this.rightHandJoints;

    if (!L || !R) {
      // Hysteresis: No cancelar el combo instantáneamente si las manos desaparecen por < 200ms
      if (this.activeCombo && now - this.lastHandDetectionTime > 200) {
        this.cancelCombo("Manos no detectadas");
        this.setGesture(GestureType.IDLE);
      }
      return;
    }
    this.lastHandDetectionTime = now;

    const cooldown = this.gestureCooldownMs[this.currentGesture] || 0;
    if (now - this.lastGestureTime < cooldown) return;

    // 1. Extraer TODAS las Poses Estáticas Atómicas detectadas en este frame
    const detectedPoses = this.evaluateValidPoses(L, R);

    // Filter by allowed powers (suppress lint)
    if (this.frameCount % 100 === 0 && this.allowedPowers.length > 0) {
      console.log(`[GestureRecognizer] Monitoring: ${this.allowedPowers.join(", ")}`);
    }

    if (detectedPoses.length > 0) {
      this.lastPoseTime = now;

      if (!this.activeCombo) {
        // Buscar iniciar un combo con CUALQUIERA de las poses detectadas
        for (const [comboName, sequence] of Object.entries(this.dynamicCombos)) {
          if (detectedPoses.includes(sequence[0])) {
            // Anti-spam para Ki Blasts si acabamos de lanzar un especial
            if (comboName.startsWith("KI_BLAST") && now - this.lastSpecialEndTime < 800) {
              continue;
            }

            console.log(`[Combo Engine] Iniciando combo: ${comboName}`);
            this.activeCombo = comboName;
            this.comboStep = 1;
            this.comboStartTime = now;
            
            // Graba la posición inicial de las manos para medir desplazamiento físico posterior
            this.leftHandStartPos = { ...L.wrist };
            this.rightHandStartPos = { ...R.wrist };
            break;
          }
        }
      } else {
        // En un combo activo, revisar si la pose esperada está entre las detectadas
        const sequence = this.dynamicCombos[this.activeCombo];
        const expectedNextPose = sequence[this.comboStep];
        
        if (detectedPoses.includes(expectedNextPose)) {
          // Validar charge_time para la Fase 2 (firing) de ataques especiales
          const id = this.activeCombo.toLowerCase();
          const powerData = (powersConfig as any)[id];
          
          if (this.comboStep === 1 && powerData?.charge_time) {
              const elapsed = (now - this.comboStartTime) / 1000;
              if (elapsed < powerData.charge_time) {
                  // Aun no ha cargado lo suficiente para disparar
                  return;
              }
          }

          this.comboStep++;
          this.consecutiveWrongPoseCount = 0;
          console.log(`[Combo Engine] Avanzando ${this.activeCombo} -> Paso ${this.comboStep}/${sequence.length}`);
          
          if (this.comboStep === sequence.length) {
            console.log(`[Combo Engine] ¡¡COMBO COMPLETADO!! => ${this.activeCombo}`);
            this.setGesture(this.activeCombo as GestureType);
            if (this.activeCombo.startsWith("KI_BLAST")) {
                this.cancelCombo("Trigger completado");
            } else {
                this.lastSpecialEndTime = now;
            }
            return;
          }
        } else if (!detectedPoses.includes(sequence[this.comboStep - 1])) {
          // Si ninguna de las poses detectadas es ni la esperada ni la anterior del mismo combo...
          this.consecutiveWrongPoseCount++;
          if (this.consecutiveWrongPoseCount >= 3) {
             this.cancelCombo("Nueva pose detectada (Interrupción)");
          }
        } else {
          this.consecutiveWrongPoseCount = 0;
        }
      }
    } else {
      this.consecutiveWrongPoseCount = 0;
      // Timeout: si el jugador pierde la postura por 2 segundos, se cancela el combo.
      if (this.activeCombo && (now - this.lastPoseTime > 1500)) {
        this.cancelCombo("Timeout de postura");
      }
    }

    // 3. Feedback visual intermedio y finalización
    if (this.activeCombo) {
      const sequence = this.dynamicCombos[this.activeCombo];
      // Mantener la emisión del combo completado si están sostenienndo la última postura
      if (this.comboStep === sequence.length) {
        this.setGesture(this.activeCombo as GestureType);
        return;
      }
      
      // Emitir PREP states si estamos en iteraciones intermedias
      if (this.activeCombo === "RECHARGING" && this.comboStep === 1) {
        this.setGesture(GestureType.RECHARGE_PREP);
        return;
      }
      if (this.activeCombo === "KAMEHAMEHA" && this.comboStep === 1) {
        this.setGesture("KAMEHAMEHA_PREP" as GestureType);
        return;
      }
    }

    if (this.currentGesture !== GestureType.IDLE) {
      this.setGesture(GestureType.IDLE);
    }
  }

  private cancelCombo(reason: string): void {
    if (this.activeCombo) {
      console.log(`[Combo Engine] Combo cancelado: ${reason}`);
    }
    this.activeCombo = null;
    this.comboStep = 0;
  }

  /**
   * Define qué poderes están disponibles y reconstruye el motor de combos.
   */
  public setAllowedPowers(powers: string[]): void {
    this.allowedPowers = powers;
    this.dynamicCombos = { ...Combos }; // Reiniciar con básicos
    
    const powersDict = powersConfig as Record<string, any>;
    for (const id of powers) {
      const details = powersDict[id];
      if (details?.vr_gestures) {
        const p1 = POSE_STRING_MAP[details.vr_gestures.preparation];
        const p2 = POSE_STRING_MAP[details.vr_gestures.firing];
        if (p1 && p2) {
          this.dynamicCombos[id.toUpperCase()] = [p1, p2];
          console.log(`[GestureRecognizer] Registrado combo dinámico: ${id}`);
        }
      }
    }
  }

  private setGesture(g: GestureType | string): void {
    if (this.currentGesture !== g) {
       this.currentGesture = g as GestureType;
       this.lastGestureTime = Date.now();
    }
  }

  getCurrentGesture(): GestureType {
    return this.currentGesture;
  }

  getLeftHandJoints() { return this.leftHandJoints; }
  getRightHandJoints() { return this.rightHandJoints; }
  
  getActiveCombo(): string | null { return this.activeCombo; }
  getComboStep(): number { return this.comboStep; }

  private isFist(hand: HandJoints): boolean {
    const threshold = 0.14; 
    // Evaluamos sólamente índice y medio, ya que el pulgar/meñique de Quest nativo suele alejarse
    return this.dist3(hand.indexTip, hand.wrist) < threshold && 
           this.dist3(hand.middleTip, hand.wrist) < threshold;
  }

  private dist3(a: { x: number; y: number; z: number }, b: { x: number; y: number; z: number }): number {
    const dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}
