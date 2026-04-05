import { HandJoints, GestureRecognizer } from "./GestureRecognizer";

/**
 * GestureSimulator
 * Herramienta de depuración para simular movimientos de manos automáticos.
 * Soporta ejecución por fases para ataques especiales.
 */
export class GestureSimulator {
  private isSimulating = false;
  private lastKiBlastHand: "left" | "right" = "right";

  // Estado para ataques especiales por fases
  private activeSpecial: string | null = null;
  private activeSpecialPhase: number = 0;

  constructor(private recognizer: GestureRecognizer) {}

  isActive(): boolean {
    return this.isSimulating;
  }

  /**
   * Ejecuta la secuencia completa de Recarga de KI.
   */
  async playRechargeSequence(): Promise<void> {
    if (this.isSimulating) return;
    this.isSimulating = true;
    console.log("[Simulator] >>> Iniciando secuencia: RECHARGE");

    const idleL = { x: -0.3, y: 1.1, z: 0.6 };
    const idleR = { x: 0.3, y: 1.1, z: 0.6 };
    const headL = { x: -0.15, y: 1.65, z: 0.4 };
    const headR = { x: 0.15, y: 1.65, z: 0.4 };
    const sideL = { x: -0.55, y: 1.3, z: 0.5 };
    const sideR = { x: 0.55, y: 1.3, z: 0.5 };

    try {
      await this.animateTo(idleL, idleR, headL, headR, 400, "fist");
      await this.delay(300);
      await this.animateTo(headL, headR, sideL, sideR, 500, "fist");
      await this.delay(800);
      await this.animateTo(sideL, sideR, idleL, idleR, 500, "normal");
    } finally {
      this.isSimulating = false;
    }
  }

  /**
   * Ráfaga de Ki básica. Si no se especifica mano, alterna automáticamente.
   */
  async playKiBlastSequence(hand?: "left" | "right"): Promise<void> {
    if (this.isSimulating) return;
    this.isSimulating = true;
    
    const targetHand = hand || (this.lastKiBlastHand === "left" ? "right" : "left");
    this.lastKiBlastHand = targetHand;
    
    console.log(`[Simulator] >>> Iniciando Ki Blast (${targetHand})`);

    const sign = targetHand === "left" ? -1 : 1;
    const idleL = { x: -0.3, y: 1.1, z: 0.6 };
    const idleR = { x: 0.3, y: 1.1, z: 0.6 };
    const prepL = { x: -0.25, y: 1.3, z: 0.15 };
    const prepR = { x: 0.25, y: 1.3, z: 0.15 };

    try {
      await this.animateTo(idleL, idleR, prepL, prepR, 200, "normal");
      await this.delay(150);

      const firePos = { x: 0.3 * sign, y: 1.3, z: 1.3 };
      const chestPos = { x: 0.1 * sign, y: 1.2, z: 0.15 };
      
      if (targetHand === "left") {
          await this.animateTo(prepL, prepR, firePos, chestPos, 100, "normal");
      } else {
          await this.animateTo(prepL, prepR, chestPos, firePos, 100, "normal");
      }
      
      await this.delay(200);
      await this.animateTo(targetHand === "left" ? firePos : chestPos, targetHand === "right" ? firePos : chestPos, idleL, idleR, 400, "normal");
    } finally {
      this.isSimulating = false;
    }
  }

  /**
   * Ráfaga cargada (siempre derecha por simplicidad de debug)
   */
  async playChargedKiBlastSequence(): Promise<void> {
    if (this.isSimulating) return;
    this.isSimulating = true;
    console.log("[Simulator] >>> Iniciando sequence: CHARGED KI BLAST");

    const idleL = { x: -0.3, y: 1.1, z: 0.6 };
    const idleR = { x: 0.3, y: 1.1, z: 0.6 };
    const prepR = { x: 0.4, y: 1.4, z: 1.2 };
    const prepL = { x: -0.1, y: 0.65, z: 0.3 };
    const fireR = { x: 0.4, y: 1.4, z: 1.6 };

    try {
      await this.animateTo(idleL, idleR, prepL, prepR, 400, "stop");
      await this.delay(1000);
      await this.animateTo(prepL, prepR, prepL, fireR, 80, "stop");
      await this.delay(300);
      await this.animateTo(prepL, fireR, idleL, idleR, 400, "normal");
    } finally {
      this.isSimulating = false;
    }
  }

  /**
   * Lógica de 2 fases para ataques especiales (Kamehameha, Final Flash, Genkidama)
   */
  async triggerSpecialPhased(type: string): Promise<void> {
    if (this.isSimulating) return;

    const idleL = { x: -0.3, y: 1.1, z: 0.6 };
    const idleR = { x: 0.3, y: 1.1, z: 0.6 };

    // Definición de posiciones por técnica
    const poses: Record<string, any> = {
      kamehameha: { prepL: { x: 0.2, y: 0.9, z: 0.4 }, prepR: { x: 0.3, y: 1.0, z: 0.4 }, fireL: { x: -0.05, y: 1.3, z: 1.4 }, fireR: { x: 0.05, y: 1.4, z: 1.4 }, type: "normal" },
      finalflash: { prepL: { x: -1.0, y: 1.4, z: 0.4 }, prepR: { x: 1.0, y: 1.4, z: 0.4 }, fireL: { x: -0.05, y: 1.4, z: 1.2 }, fireR: { x: 0.05, y: 1.4, z: 1.2 }, type: "normal" },
      genkidama:  { prepL: { x: -0.3, y: 2.1, z: 0.3 }, prepR: { x: 0.3, y: 2.1, z: 0.3 }, fireL: { x: -0.1, y: 1.3, z: 1.3 }, fireR: { x: 0.1, y: 1.3, z: 1.3 }, type: "back" }
    };

    const config = poses[type.toLowerCase()];
    if (!config) return;

    this.isSimulating = true;

    try {
      if (this.activeSpecial !== type) {
        // FASE 1: Preparación
        console.log(`[Simulator] >>> ${type.toUpperCase()} FASE 1: Prep`);
        if (type === "genkidama") this.recognizer.setCameraForward({ x: 0, y: 0.85, z: 0.4 });
        
        await this.animateTo(idleL, idleR, config.prepL, config.prepR, 600, config.type);
        this.activeSpecial = type;
        this.activeSpecialPhase = 1;
      } else {
        // FASE 2: Disparo
        console.log(`[Simulator] >>> ${type.toUpperCase()} FASE 2: Fire`);
        if (type === "genkidama") this.recognizer.setCameraForward({ x: 0, y: 0, z: 1 });

        await this.animateTo(config.prepL, config.prepR, config.fireL, config.fireR, 200, "normal");
        await this.delay(600);
        await this.animateTo(config.fireL, config.fireR, idleL, idleR, 600, "normal");
        
        this.activeSpecial = null;
        this.activeSpecialPhase = 0;
      }
    } finally {
      this.isSimulating = false;
    }
  }

  private async animateTo(
    startL: any, startR: any,
    endL: any, endR: any,
    duration: number,
    poseType: "normal" | "stop" | "back" | "fist" | boolean
  ): Promise<void> {
    const startTime = performance.now();
    
    return new Promise((resolve) => {
      const step = (now: number) => {
        const elapsed = now - startTime;
        const progress = Math.min(elapsed / duration, 1);
        const t = progress * (2 - progress);

        const currentL = this.lerpPos(startL, endL, t);
        const currentR = this.lerpPos(startR, endR, t);

        this.recognizer.updateHandJoints("left", this.createHand(currentL, poseType));
        this.recognizer.updateHandJoints("right", this.createHand(currentR, poseType));

        if (progress < 1) requestAnimationFrame(step);
        else resolve();
      };
      requestAnimationFrame(step);
    });
  }

  private lerpPos(a: any, b: any, t: number) {
    return {
      x: a.x + (b.x - a.x) * t,
      y: a.y + (b.y - a.y) * t,
      z: a.z + (b.z - a.z) * t,
    };
  }

  private createHand(wrist: any, poseType: "normal" | "stop" | "back" | "fist" | boolean): HandJoints {
    const isFist = poseType === true || poseType === "fist";
    const offsetZ = isFist ? 0.04 : 0.16;
    let offsetY = 0;
    let finalZ = wrist.z + offsetZ;

    if (poseType === "stop") {
      offsetY = 0.15;
      finalZ = wrist.z;
    } else if (poseType === "back") {
      offsetY = 0.15;
      finalZ = wrist.z - 0.12; 
    }

    return {
      wrist,
      thumbTip:  { x: wrist.x + offsetZ, y: wrist.y, z: finalZ },
      indexTip:  { x: wrist.x, y: wrist.y + offsetY, z: finalZ },
      middleTip: { x: wrist.x, y: wrist.y + offsetY, z: finalZ },
      ringTip:   { x: wrist.x, y: wrist.y + offsetY, z: finalZ },
      littleTip: { x: wrist.x, y: wrist.y + offsetY, z: finalZ },
    };
  }

  private delay(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
