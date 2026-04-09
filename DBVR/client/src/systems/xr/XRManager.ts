import {
  Scene,
  WebXRFeatureName,
  WebXRDefaultExperience,
  WebXRHandTracking,
  WebXRHandJoint,
  WebXRHand
} from "@babylonjs/core";
import { InputManager } from "../input/InputManager";
import { PlayerController } from "../input/PlayerController";
import { VRHud } from "../../ui/VRHud";
import { HUD } from "../../ui/HUD";
import { GestureDebugOverlay } from "../gestures/GestureDebugOverlay";
import { XRHandsContext } from "../gestures/GestureSkillSystem";
import { EnvironmentManager } from "../vfx/EnvironmentManager";

export interface XRManagerConfig {
    scene: Scene;
    xrOverlay: HTMLElement;
    inputManager: InputManager;
    playerController: PlayerController;
    vrHud: VRHud;
    hud: HUD;
    debugOverlay: GestureDebugOverlay;
    envManager: EnvironmentManager;
}

export class XRManager {
  private scene: Scene;
  private xrOverlay: HTMLElement;
  private inputManager: InputManager;
  private playerController: PlayerController;
  private vrHud: VRHud;
  private hud: HUD;
  private debugOverlay: GestureDebugOverlay;
  private envManager: EnvironmentManager;

  private xr: WebXRDefaultExperience | null = null;

  constructor(config: XRManagerConfig) {
    this.scene = config.scene;
    this.xrOverlay = config.xrOverlay;
    this.inputManager = config.inputManager;
    this.playerController = config.playerController;
    this.vrHud = config.vrHud;
    this.hud = config.hud;
    this.debugOverlay = config.debugOverlay;
    this.envManager = config.envManager;
  }

  public async init(): Promise<boolean> {
    if (!navigator.xr) {
        console.log("[XRManager] navigator.xr no disponible — modo desktop");
        return false;
    }

    const supported = await navigator.xr.isSessionSupported("immersive-vr").catch(() => false);
    if (!supported) {
        console.log("[XRManager] immersive-vr no soportado");
        return false;
    }

    try {
      const xrConfig: any = {
        uiOptions: { sessionMode: "immersive-vr", referenceSpaceType: "local-floor" },
        optionalFeatures: ["hand-tracking", "dom-overlay"],
        domOverlay: { element: this.xrOverlay },
      };
      
      this.xr = await this.scene.createDefaultXRExperienceAsync(xrConfig);
      if (!this.xr) return false;

      this.inputManager.getGSS().setXRExperience(this.xr);
      this.setupXRExperience();
      this.setupHandTracking();
      console.log("[XRManager] WebXR inicializado correctamente");
      return true;
    } catch (e) {
      console.warn("[XRManager] Error al inicializar WebXR:", e);
      return false;
    }
  }

  private setupXRExperience(): void {
    if (!this.xr) return;

    try { 
      this.xr.baseExperience.featuresManager.enableFeature(WebXRFeatureName.POINTER_SELECTION, "latest", {
        xrInput: this.xr.input,
        enablePointerSelectionOnAllControllers: true
      });
    } catch(e){}
    try { this.xr.baseExperience.featuresManager.disableFeature(WebXRFeatureName.TELEPORTATION); } catch(e){}

    this.xr.baseExperience.onStateChangedObservable.add((state: number) => {
      const inXR = state === 2; // IN_XR
      if (inXR) {
        const xrCamera = this.xr!.baseExperience.camera;
        if (xrCamera && this.vrHud) {
          this.xr!.baseExperience.sessionManager.onXRFrameObservable.addOnce(() => {
            this.vrHud.attachToXRCamera(xrCamera);
          });
        }
        this.hud?.hide?.();
      } else {
        this.vrHud?.detachFromCamera();
        this.hud?.show?.();
      }
      
      const leftMesh = this.scene.getMeshByName("leftHand");
      const rightMesh = this.scene.getMeshByName("rightHand");
      if (leftMesh) leftMesh.isVisible = !inXR;
      if (rightMesh) rightMesh.isVisible = !inXR;
    });
  }

  private setupHandTracking(): void {
    if (!this.xr) return;

    let handTracking: WebXRHandTracking | null = null;
    try {
      handTracking = this.xr.baseExperience.featuresManager.enableFeature(
        WebXRFeatureName.HAND_TRACKING, "latest",
        { xrInput: this.xr.input, jointMeshes: { disableDefaultHandMesh: false, enablePhysics: false } }
      ) as WebXRHandTracking;
    } catch (e) {
      console.warn("[XRManager] Hand tracking no disponible:", e);
    }

    if (handTracking) {
      let leftHand: WebXRHand | null = null;
      let rightHand: WebXRHand | null = null;

      // 1. Detectar manos ya existentes al momento de habilitar el feature
      const existingHands = (handTracking as any).hands;
      if (existingHands) {
          if (existingHands.left) { 
              leftHand = existingHands.left; 
              console.log("[XRManager] Mano IZQUIERDA pre-existente detectada");
          }
          if (existingHands.right) { 
              rightHand = existingHands.right; 
              console.log("[XRManager] Mano DERECHA pre-existente detectada");
          }
      }

      handTracking.onHandAddedObservable?.add((hand: any) => {
        const hnd = hand.handedness || hand.xrController?.inputSource?.handedness;
        console.log(`[XRManager] Mano DETECTADA por evento: ${hnd}`);
        if (hnd === "left") leftHand = hand;
        if (hnd === "right") rightHand = hand;
      });

      handTracking.onHandRemovedObservable?.add((hand: any) => {
        const hnd = hand.handedness || hand.xrController?.inputSource?.handedness;
        console.log(`[XRManager] Mano PERDIDA por evento: ${hnd}`);
        if (hnd === "left") leftHand = null;
        if (hnd === "right") rightHand = null;
      });

      this.scene.registerBeforeRender(() => {
        const xrCamera = this.xr?.baseExperience.camera;
        if (!xrCamera) return;

        const ctx: XRHandsContext = {
            leftWrist: leftHand?.getJointMesh(WebXRHandJoint.WRIST),
            rightWrist: rightHand?.getJointMesh(WebXRHandJoint.WRIST),
            leftHand: leftHand || undefined,
            rightHand: rightHand || undefined,
            headPos: xrCamera.globalPosition,
            deltaTimeMs: this.scene.getEngine().getDeltaTime()
        };

        this.inputManager.update(ctx);
        const gss = this.inputManager.getGSS();
        const currentGesture = gss.currentState;
        const handTrackingActive = !!(ctx.leftWrist || ctx.rightWrist);

        const leftJoints = leftHand ? {
            wrist: leftHand.getJointMesh(WebXRHandJoint.WRIST)?.absolutePosition,
            indexTip: leftHand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP)?.absolutePosition
        } : null;

        const rightJoints = rightHand ? {
            wrist: rightHand.getJointMesh(WebXRHandJoint.WRIST)?.absolutePosition,
            indexTip: rightHand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP)?.absolutePosition
        } : null;

        this.debugOverlay?.update({
          handTrackingActive,
          leftJoints,
          rightJoints,
          gesture: currentGesture,
          handApiSource: leftHand || rightHand ? "WebXR Hands" : "waiting...",
        });

        this.vrHud?.updateHandTrackingDebug(
            !!leftHand, !!rightHand, 
            leftJoints, rightJoints, 
            currentGesture, 
            leftHand || rightHand ? "WebXR Hands" : "waiting..."
        );

        if (ctx.leftWrist && ctx.rightWrist) {
            const headPos = xrCamera.globalPosition;
            const headRot = xrCamera.rotationQuaternion;
            
            if (headRot) {
                const combat = this.playerController["combat"];
                this.envManager.updateEnemyMirror(
                    combat?.mirrorMode || false,
                    headPos,
                    headRot,
                    ctx.leftWrist.absolutePosition,
                    ctx.rightWrist.absolutePosition
                );
            }
        }
      });
    }
  }

  public async enterVR(): Promise<void> {
    if (this.xr) {
      await this.xr.baseExperience.enterXRAsync('immersive-vr', 'local-floor');
      return;
    }

    // Polling con timeout y Promise adecuada
    return new Promise((resolve, reject) => {
      const maxWait = 8000;
      const interval = 200;
      let waited = 0;

      const check = setInterval(async () => {
        waited += interval;
        if (this.xr) {
          clearInterval(check);
          try {
            await this.xr.baseExperience.enterXRAsync('immersive-vr', 'local-floor');
            resolve();
          } catch (err) {
            reject(err);
          }
        } else if (waited >= maxWait) {
          clearInterval(check);
          reject(new Error('[XRManager] Timeout esperando XR experience'));
        }
      }, interval);
    });
  }

  public getXR(): WebXRDefaultExperience | null {
    return this.xr;
  }

  public async exitXR(): Promise<void> {
    if (this.xr?.baseExperience?.state === 2) {
        await this.xr.baseExperience.exitXRAsync();
    }
  }
}
