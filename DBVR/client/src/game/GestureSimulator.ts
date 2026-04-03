import { HandJoints, GestureRecognizer } from "./GestureRecognizer";

/**
 * GestureSimulator
 * Herramienta de depuración para simular movimientos de manos automáticos
 * y verificar la lógica de gestos en dos fases sin hardware VR.
 */
export class GestureSimulator {
  private isSimulating = false;

  constructor(private recognizer: GestureRecognizer) {}

  isActive(): boolean {
    return this.isSimulating;
  }

  /**
   * Ejecuta la secuencia completa de Recarga de KI:
   * 1. Sube manos a la cabeza (Fase 1)
   * 2. Mueve manos a los lados (Fase 2)
   */
  async playRechargeSequence(): Promise<void> {
    if (this.isSimulating) {
      console.warn("[Simulator] Ya hay una simulación en curso.");
      return;
    }
    this.isSimulating = true;
    console.log("[Simulator] >>> Iniciando secuencia automatizada: RECHARGE");

    const idleL = { x: -0.3, y: 1.1, z: 0.6 };
    const idleR = { x: 0.3, y: 1.1, z: 0.6 };
    const headL = { x: -0.15, y: 1.65, z: 0.4 };
    const headR = { x: 0.15, y: 1.65, z: 0.4 };
    const sideL = { x: -0.55, y: 1.3, z: 0.5 };
    const sideR = { x: 0.55, y: 1.3, z: 0.5 };

    try {
      // 1. Preparación: De Reposo a Cabeza (Puños cerrados)
      await this.animateTo(idleL, idleR, headL, headR, 600, true);
      await this.delay(400); // Mantener en fase 1

      // 2. Activación: De Cabeza a Lados "L" (Puños cerrados)
      await this.animateTo(headL, headR, sideL, sideR, 800, true);
      await this.delay(500);

      // 3. Retorno suave a reposo (Puños abiertos)
      await this.animateTo(sideL, sideR, idleL, idleR, 800, false);
      
    } catch (e) {
      console.error("[Simulator] Error en simulación:", e);
    } finally {
      this.isSimulating = false;
      console.log("[Simulator] >>> Simulación finalizada.");
    }
  }

  async playKiBlastSequence(hand: "left" | "right"): Promise<void> {
    if (this.isSimulating) {
      console.warn("[Simulator] Ya hay una simulación en curso.");
      return;
    }
    this.isSimulating = true;
    console.log(`[Simulator] >>> Iniciando Ki Blast Simulator (${hand})`);

    const sign = hand === "left" ? -1 : 1;
    const idle = { x: 0.3 * sign, y: 1.1, z: 0.6 };
    const prep = { x: 0.3 * sign, y: 1.3, z: 0.5 };
    const thrust = { x: 0.3 * sign, y: 1.3, z: 1.3 }; // Thrust > 0.02 delta per frame easily

    try {
      // 1. Preparación: Pose Stop
      await this.animateToSingle(hand, idle, prep, 200, "stop");
      await this.delay(200); 

      // 2. Thrust adelante (Aceleración)
      // Debe ser lo suficientemente rápido para superar el threshold de velocidad
      await this.animateToSingle(hand, prep, thrust, 100, "stop");
      await this.delay(300);

      // 3. Volver a reposo
      await this.animateToSingle(hand, thrust, idle, 400, "normal");
      
    } catch (e) {
      console.error("[Simulator] Error en simulación:", e);
    } finally {
      this.isSimulating = false;
    }
  }

  private async animateTo(
    startL: any, startR: any,
    endL: any, endR: any,
    duration: number,
    fist: boolean
  ): Promise<void> {
    const startTime = performance.now();
    
    return new Promise((resolve) => {
      const step = (now: number) => {
        const elapsed = now - startTime;
        const progress = Math.min(elapsed / duration, 1);
        
        // Easing cuadratica para movimiento natural
        const t = progress * (2 - progress);

        const currentL = this.lerpPos(startL, endL, t);
        const currentR = this.lerpPos(startR, endR, t);

        this.recognizer.updateHandJoints("left", this.createHand(currentL, fist));
        this.recognizer.updateHandJoints("right", this.createHand(currentR, fist));

        if (progress < 1) {
          requestAnimationFrame(step);
        } else {
          resolve();
        }
      };
      requestAnimationFrame(step);
    });
  }

  private async animateToSingle(
    hand: "left" | "right",
    start: any, end: any,
    duration: number,
    poseType: "normal" | "stop" | "fist"
  ): Promise<void> {
    const startTime = performance.now();
    
    return new Promise((resolve) => {
      const step = (now: number) => {
        const elapsed = now - startTime;
        const progress = Math.min(elapsed / duration, 1);
        const t = progress * (2 - progress);
        const current = this.lerpPos(start, end, t);

        this.recognizer.updateHandJoints(hand, this.createHand(current, poseType));

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

  private createHand(wrist: any, poseType: "normal" | "stop" | "fist" | boolean): HandJoints {
    const isFist = poseType === true || poseType === "fist";
    const offsetZ = isFist ? 0.04 : 0.16;
    let offsetY = 0;
    let finalZ = wrist.z + offsetZ;

    if (poseType === "stop") {
      offsetY = 0.15; // Dedos arriba de la muñeca
      finalZ = wrist.z;
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
