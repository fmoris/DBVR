/**
 * GestureRecognizer
 * Detecta gestos de manos basado en posiciones de articulaciones WebXR
 */

import { GestureType, HandJoints } from '../types';

export class GestureRecognizer {
  private leftHandJoints: HandJoints | null = null;
  private rightHandJoints: HandJoints | null = null;
  private currentGesture: GestureType = GestureType.IDLE;
  private gestureThresholds = {
    chargeDistance: 0.15, // Distancia mínima entre manos para cargar
    blockAngle: 45, // Ángulo mínimo para bloqueo cruzado
    parrySpeed: 0.5, // Velocidad mínima para repulsión
  };

  /**
   * Actualizar posiciones de articulaciones
   */
  updateHandJoints(hand: 'left' | 'right', joints: HandJoints): void {
    if (hand === 'left') {
      this.leftHandJoints = joints;
    } else {
      this.rightHandJoints = joints;
    }

    this.recognizeGesture();
  }

  /**
   * Reconocer el gesto actual basado en posiciones de manos
   */
  private recognizeGesture(): void {
    if (!this.leftHandJoints || !this.rightHandJoints) {
      this.currentGesture = GestureType.IDLE;
      return;
    }

    // Calcular distancia entre muñecas
    const wristDistance = this.calculateDistance(
      this.leftHandJoints.wrist,
      this.rightHandJoints.wrist
    );

    // Calcular posición promedio de las manos
    const handsCenter = {
      x: (this.leftHandJoints.wrist.x + this.rightHandJoints.wrist.x) / 2,
      y: (this.leftHandJoints.wrist.y + this.rightHandJoints.wrist.y) / 2,
      z: (this.leftHandJoints.wrist.z + this.rightHandJoints.wrist.z) / 2,
    };

    // Detectar carga de ataque (manos juntas en el pecho)
    if (wristDistance < this.gestureThresholds.chargeDistance) {
      this.currentGesture = GestureType.CHARGING;
      return;
    }

    // Detectar bloqueo (brazos cruzados)
    if (this.isBlockingPosture()) {
      this.currentGesture = GestureType.BLOCKING;
      return;
    }

    // Detectar ataque (manos empujadas hacia adelante)
    if (this.isAttackingPosture(handsCenter)) {
      this.currentGesture = GestureType.ATTACKING;
      return;
    }

    // Detectar recarga de KI (puños cerrados a los lados)
    if (this.isRechargingPosture()) {
      this.currentGesture = GestureType.RECHARGING;
      return;
    }

    this.currentGesture = GestureType.IDLE;
  }

  /**
   * Detectar postura de bloqueo (brazos cruzados)
   */
  private isBlockingPosture(): boolean {
    if (!this.leftHandJoints || !this.rightHandJoints) return false;

    // Ambas manos deben estar cerca del cuerpo (frente al pecho)
    const leftY = this.leftHandJoints.wrist.y;
    const rightY = this.rightHandJoints.wrist.y;
    const leftZ = this.leftHandJoints.wrist.z;
    const rightZ = this.rightHandJoints.wrist.z;

    // Verificar que las manos estén cruzadas (una adelante de la otra en Z)
    const zDifference = Math.abs(leftZ - rightZ);
    const yDifference = Math.abs(leftY - rightY);

    return zDifference > 0.1 && yDifference < 0.3;
  }

  /**
   * Detectar postura de ataque (manos empujadas hacia adelante)
   */
  private isAttackingPosture(_handsCenter: { x: number; y: number; z: number }): boolean {
    if (!this.leftHandJoints || !this.rightHandJoints) return false;

    // Las manos deben estar extendidas hacia adelante (Z positivo)
    const avgZ = (this.leftHandJoints.wrist.z + this.rightHandJoints.wrist.z) / 2;
    
    // Si el promedio de Z es positivo y las manos están separadas, es un ataque
    const wristDistance = this.calculateDistance(
      this.leftHandJoints.wrist,
      this.rightHandJoints.wrist
    );

    return avgZ > 0.2 && wristDistance > 0.2;
  }

  /**
   * Detectar postura de recarga (puños cerrados a los lados)
   */
  private isRechargingPosture(): boolean {
    if (!this.leftHandJoints || !this.rightHandJoints) return false;

    // Las manos deben estar a los lados del cuerpo
    const leftX = this.leftHandJoints.wrist.x;
    const rightX = this.rightHandJoints.wrist.x;

    // Verificar que estén separadas lateralmente
    return Math.abs(leftX - rightX) > 0.3 && 
           this.leftHandJoints.wrist.z < 0.1 && 
           this.rightHandJoints.wrist.z < 0.1;
  }

  /**
   * Calcular distancia euclidiana entre dos puntos
   */
  private calculateDistance(
    p1: { x: number; y: number; z: number },
    p2: { x: number; y: number; z: number }
  ): number {
    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    const dz = p2.z - p1.z;
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /**
   * Getters
   */
  getCurrentGesture(): GestureType {
    return this.currentGesture;
  }

  getLeftHandJoints(): HandJoints | null {
    return this.leftHandJoints;
  }

  getRightHandJoints(): HandJoints | null {
    return this.rightHandJoints;
  }
}
