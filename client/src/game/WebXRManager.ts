/**
 * WebXRManager
 * Gestiona la experiencia WebXR y el seguimiento de manos
 */

import * as BABYLON from "@babylonjs/core";

interface HandJoints {
  wrist: { x: number; y: number; z: number };
  thumbTip: { x: number; y: number; z: number };
  indexTip: { x: number; y: number; z: number };
  middleTip: { x: number; y: number; z: number };
  ringTip: { x: number; y: number; z: number };
  littleTip: { x: number; y: number; z: number };
}

export class WebXRManager {
  private xrHelper: BABYLON.WebXRDefaultExperience | null = null;
  private handTracking: any = null;
  private leftHandJoints: HandJoints | null = null;
  private rightHandJoints: HandJoints | null = null;

  constructor(private scene: BABYLON.Scene) {}

  /**
   * Inicializar WebXR
   */
  async initializeWebXR(): Promise<boolean> {
    try {
      // Crear experiencia XR por defecto
      this.xrHelper = await this.scene.createDefaultXRExperienceAsync({
        uiOptions: {
          sessionMode: "immersive-vr",
          referenceSpaceType: "local-floor",
        },
        optionalFeatures: [
          "hand-tracking",
          "dom-overlay",
          "dom-overlay-for-handheld",
        ],
      });

      // WebXR inicializado correctamente

      // Habilitar hand tracking
      const featureManager = this.xrHelper.baseExperience.featuresManager;
      this.handTracking = featureManager.enableFeature(
        BABYLON.WebXRFeatureName.HAND_TRACKING,
        "latest",
        {
          xrInput: this.xrHelper.input,
          jointMeshes: {
            disableDefaultHandMesh: true,
            invisible: true,
          },
        }
      );

      console.log("✅ WebXR inicializado correctamente");
      return true;
    } catch (error) {
      console.error("❌ Error al inicializar WebXR:", error);
      return false;
    }
  }

  /**
   * Actualizar posiciones de manos
   */
  updateHandTracking(): void {
    if (!this.handTracking) return;

    // Obtener manos rastreadas
    const hands = this.handTracking.hands;

    if (hands.left) {
      this.leftHandJoints = this.extractHandJoints(hands.left);
    }

    if (hands.right) {
      this.rightHandJoints = this.extractHandJoints(hands.right);
    }
  }

  /**
   * Extraer articulaciones de una mano
   */
  private extractHandJoints(hand: any): HandJoints {
    const joints: HandJoints = {
      wrist: this.getJointPosition(hand, 0),
      thumbTip: this.getJointPosition(hand, 4),
      indexTip: this.getJointPosition(hand, 8),
      middleTip: this.getJointPosition(hand, 12),
      ringTip: this.getJointPosition(hand, 16),
      littleTip: this.getJointPosition(hand, 20),
    };

    return joints;
  }

  /**
   * Obtener posición de una articulación específica
   */
  private getJointPosition(
    hand: any,
    jointIndex: number
  ): { x: number; y: number; z: number } {
    try {
      const joint = hand.joints[jointIndex];
      if (joint && joint.position) {
        return {
          x: joint.position.x,
          y: joint.position.y,
          z: joint.position.z,
        };
      }
    } catch (e) {
      // Articulación no disponible
    }

    return { x: 0, y: 0, z: 0 };
  }

  /**
   * Getters
   */
  getLeftHandJoints(): HandJoints | null {
    return this.leftHandJoints;
  }

  getRightHandJoints(): HandJoints | null {
    return this.rightHandJoints;
  }

  isHandTrackingAvailable(): boolean {
    return this.handTracking !== null;
  }

  getXRHelper(): BABYLON.WebXRDefaultExperience | null {
    return this.xrHelper;
  }

  /**
   * Entrar en modo VR
   */
  async enterVR(): Promise<void> {
    if (this.xrHelper) {
      await this.xrHelper.baseExperience.enterXRAsync("immersive-vr", "local");
    }
  }

  /**
   * Salir de modo VR
   */
  async exitVR(): Promise<void> {
    if (this.xrHelper) {
      await this.xrHelper.baseExperience.exitXRAsync();
    }
  }
}