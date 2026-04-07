import {
  Scene,
  WebXRFeatureName,
  WebXRDefaultExperience,
  WebXRHandTracking,
  WebXRHandJoint
} from "@babylonjs/core";
import { InputManager } from "./InputManager";
import { PlayerController } from "./PlayerController";
import { VRHud } from "./VRHud";
import { HUD } from "./HUD";
import { GestureDebugOverlay } from "./GestureDebugOverlay";
import { XRHandsContext } from "./GestureSkillSystem";
import { EnvironmentManager } from "./EnvironmentManager";

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

  public async init(): Promise<void> {
    if (!navigator.xr) {
        console.log("[XRManager] navigator.xr no disponible — modo desktop");
        return;
    }

    const supported = await navigator.xr.isSessionSupported("immersive-vr").catch(() => false);
    if (!supported) {
        console.log("[XRManager] immersive-vr no soportado");
        return;
    }

    try {
      const xrConfig: any = {
        uiOptions: { sessionMode: "immersive-vr", referenceSpaceType: "local-floor" },
        optionalFeatures: ["hand-tracking", "dom-overlay"],
        domOverlay: { element: this.xrOverlay },
      };
      
      this.xr = await this.scene.createDefaultXRExperienceAsync(xrConfig);
      if (!this.xr) return;

      this.inputManager.getGSS().setXRExperience(this.xr);
      this.setupXRExperience();
      this.setupHandTracking();
      console.log("[XRManager] WebXR inicializado correctamente");
    } catch (e) {
      console.warn("[XRManager] Error al inicializar WebXR:", e);
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
        { xrInput: this.xr.input, jointMeshes: { disableDefaultHandMesh: true, enablePhysics: false } }
      ) as WebXRHandTracking;
    } catch (e) {
      console.warn("[XRManager] Hand tracking no disponible:", e);
    }

    if (handTracking) {
      let leftHand: any = null;
      let rightHand: any = null;

      handTracking.onHandAddedObservable?.add((hand: any) => {
        const hnd = hand.xrController?.inputSource?.handedness ?? hand.handedness;
        console.log(`[XRManager] Mano DETECTADA: ${hnd}`);
        if (hnd === "left") leftHand = hand;
        if (hnd === "right") rightHand = hand;
      });

      handTracking.onHandRemovedObservable?.add((hand: any) => {
        const hnd = hand.xrController?.inputSource?.handedness ?? hand.handedness;
        console.log(`[XRManager] Mano PERDIDA: ${hnd}`);
        if (hnd === "left") leftHand = null;
        if (hnd === "right") rightHand = null;
      });

      this.scene.registerBeforeRender(() => {
        const xrCamera = this.xr?.baseExperience.camera;
        if (!xrCamera) return;

        const ctx: XRHandsContext = {
            leftWrist: leftHand?.getJointMesh(WebXRHandJoint.WRIST) || leftHand?.getJointMesh("wrist"),
            rightWrist: rightHand?.getJointMesh(WebXRHandJoint.WRIST) || rightHand?.getJointMesh("wrist"),
            leftHand: leftHand,
            rightHand: rightHand,
            headPos: xrCamera.globalPosition,
            deltaTimeMs: this.scene.getEngine().getDeltaTime()
        };

        this.inputManager.update(ctx);
        const gss = this.inputManager.getGSS();
        const currentGesture = gss.currentState;
        const handTrackingActive = !!(ctx.leftWrist || ctx.rightWrist);

        this.debugOverlay?.update({
          handTrackingActive,
          leftJoints: null,
          rightJoints: null,
          gesture: currentGesture,
          handApiSource: leftHand || rightHand ? "WebXR Hands" : "waiting...",
        });

        this.vrHud?.updateHandTrackingDebug(
            !!leftHand, !!rightHand, 
            null, null, 
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
    } else {
      let waited = 0;
      const t = setInterval(async () => {
        waited += 200;
        if (this.xr) {
          clearInterval(t);
          await this.xr.baseExperience.enterXRAsync('immersive-vr', 'local-floor');
        } else if (waited >= 8000) clearInterval(t);
      }, 200);
    }
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
