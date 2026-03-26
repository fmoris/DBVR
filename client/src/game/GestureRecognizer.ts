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
 * Extrae los joints de un WebXRHand de Babylon (acceso por nombre de joint)
 * Soporta tanto el acceso por Map (joints.get(name)) como por índice numérico
 * como fallback para versiones antiguas de Babylon.
 */
export function extractHandJoints(hand: any): HandJoints | null {
  if (!hand) return null;

  const get = (name: string, fallbackIdx: number): { x: number; y: number; z: number } => {
    try {
      // Babylon 6+: hand.getJointMesh(name) o hand.joints como Map
      let joint: any = null;

      if (typeof hand.getJointMesh === "function") {
        joint = hand.getJointMesh(name);
      } else if (hand.joints instanceof Map) {
        joint = hand.joints.get(name);
      } else if (hand.joints && typeof hand.joints === "object") {
        // Acceso por nombre como objeto
        joint = hand.joints[name] ?? hand.joints[fallbackIdx];
      }

      if (joint?.position) {
        return { x: joint.position.x, y: joint.position.y, z: joint.position.z };
      }
      // Fallback: acceso por índice numérico (Babylon < 6.x)
      if (hand.joints && hand.joints[fallbackIdx]?.position) {
        const p = hand.joints[fallbackIdx].position;
        return { x: p.x, y: p.y, z: p.z };
      }
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

export class GestureRecognizer {
  private leftHandJoints:  HandJoints | null = null;
  private rightHandJoints: HandJoints | null = null;
  private currentGesture: GestureType = GestureType.IDLE;

  // Cooldown por gesto para evitar spam (ms)
  private lastGestureTime = 0;
  private gestureCooldownMs: Record<GestureType, number> = {
    [GestureType.IDLE]:       0,
    [GestureType.ATTACKING]:  600,   // ataque básico: máx ~1.6/s
    [GestureType.CHARGING]:   200,   // carga: se mantiene activa
    [GestureType.BLOCKING]:   150,
    [GestureType.PARRYING]:   400,
    [GestureType.RECHARGING]: 200,
  };

  // Historial para detectar movimientos (ataque = empuje hacia adelante)
  private prevLeftZ  = 0;
  private prevRightZ = 0;
  private frameCount = 0;

  constructor(_scene?: any) {}

  updateHandJoints(hand: "left" | "right", joints: HandJoints): void {
    if (hand === "left") {
      this.prevLeftZ = this.leftHandJoints?.wrist.z ?? joints.wrist.z;
      this.leftHandJoints = joints;
    } else {
      this.prevRightZ = this.rightHandJoints?.wrist.z ?? joints.wrist.z;
      this.rightHandJoints = joints;
    }
    this.frameCount++;
    // Reconocer solo cada 2 frames para reducir carga
    if (this.frameCount % 2 === 0) this.recognizeGesture();
  }

  private recognizeGesture(): void {
    const L = this.leftHandJoints;
    const R = this.rightHandJoints;

    if (!L || !R) {
      this.currentGesture = GestureType.IDLE;
      return;
    }

    const now = Date.now();
    const cooldown = this.gestureCooldownMs[this.currentGesture];
    if (now - this.lastGestureTime < cooldown) return;

    // ── 1. BLOQUEO: muñecas a la misma altura, una delante de la otra ──────
    //    Brazos cruzados frente al cuerpo: diferencia en Z > 12cm, Y similar
    const zDiff = Math.abs(L.wrist.z - R.wrist.z);
    const yDiff = Math.abs(L.wrist.y - R.wrist.y);
    if (zDiff > 0.12 && yDiff < 0.25) {
      this.setGesture(GestureType.BLOCKING);
      return;
    }

    // ── 2. CARGA: muñecas juntas frente al pecho (distancia < 18cm) ────────
    const wristDist = this.dist3(L.wrist, R.wrist);
    if (wristDist < 0.18) {
      this.setGesture(GestureType.CHARGING);
      return;
    }

    // ── 3. ATAQUE: empuje hacia adelante (movimiento en -Z en local-floor) ──
    //    En local-floor, "adelante" es -Z. Detectamos velocidad de empuje.
    const leftPush  = this.prevLeftZ  - L.wrist.z;  // positivo = avanza hacia -Z
    const rightPush = this.prevRightZ - R.wrist.z;
    if (leftPush > 0.04 && rightPush > 0.04) {
      this.setGesture(GestureType.ATTACKING);
      return;
    }

    // ── 4. RECARGA: brazos abiertos a los lados, manos bajas ───────────────
    //    Muñecas separadas > 50cm en X, Z neutro (no empujadas)
    const xDist = Math.abs(L.wrist.x - R.wrist.x);
    const avgZ  = (L.wrist.z + R.wrist.z) / 2;
    if (xDist > 0.50 && Math.abs(avgZ) < 0.35) {
      this.setGesture(GestureType.RECHARGING);
      return;
    }

    this.currentGesture = GestureType.IDLE;
  }

  private setGesture(g: GestureType): void {
    this.currentGesture = g;
    this.lastGestureTime = Date.now();
  }

  private dist3(
    a: { x: number; y: number; z: number },
    b: { x: number; y: number; z: number }
  ): number {
    const dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  getCurrentGesture(): GestureType { return this.currentGesture; }
  getLeftHandJoints():  HandJoints | null { return this.leftHandJoints; }
  getRightHandJoints(): HandJoints | null { return this.rightHandJoints; }
}
