import {
  Scene,
  WebXRFeatureName,
  WebXRDefaultExperience,
  WebXRHandTracking
} from "@babylonjs/core";
import { InputManager } from "./InputManager";
import { PlayerController } from "./PlayerController";
import { VRHud } from "./VRHud";
import { HUD } from "./HUD";
import { GestureDebugOverlay } from "./GestureDebugOverlay";
import { extractHandJoints } from "./GestureRecognizer";
import { GameEngine } from "./GameEngine";

export interface XRManagerConfig {
    scene: Scene;
    xrOverlay: HTMLElement;
    inputManager: InputManager;
    playerController: PlayerController;
    vrHud: VRHud;
    hud: HUD;
    debugOverlay: GestureDebugOverlay;
    engineManager: GameEngine;
}

export class XRManager {
  private scene: Scene;
  private xrOverlay: HTMLElement;
  private inputManager: InputManager;
  private playerController: PlayerController;
  private vrHud: VRHud;
  private hud: HUD;
  private debugOverlay: GestureDebugOverlay;
  private engineManager: GameEngine;

  private xr: WebXRDefaultExperience | null = null;

  constructor(config: XRManagerConfig) {
    this.scene = config.scene;
    this.xrOverlay = config.xrOverlay;
    this.inputManager = config.inputManager;
    this.playerController = config.playerController;
    this.vrHud = config.vrHud;
    this.hud = config.hud;
    this.debugOverlay = config.debugOverlay;
    this.engineManager = config.engineManager;
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

      this.setupXRExperience();
      this.setupHandTracking();
      console.log("[XRManager] WebXR inicializado correctamente");
    } catch (e) {
      console.warn("[XRManager] Error al inicializar WebXR:", e);
    }
  }

  private setupXRExperience(): void {
    if (!this.xr) return;

    try { this.xr.baseExperience.featuresManager.disableFeature(WebXRFeatureName.POINTER_SELECTION); } catch(e){}
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
      
      // Update hand palm visibility handled by meshes in Game/PlayerController
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
        if (hnd === "left") leftHand = hand;
        if (hnd === "right") rightHand = hand;
      });

      handTracking.onHandRemovedObservable?.add((hand: any) => {
        const hnd = hand.xrController?.inputSource?.handedness ?? hand.handedness;
        if (hnd === "left") leftHand = null;
        if (hnd === "right") rightHand = null;
      });

      this.scene.registerBeforeRender(() => {
        if (this.xr?.baseExperience.state !== 2) return;

        const G = this.inputManager.getGestureRecognizer();
        const xrCamera = this.xr?.baseExperience.camera;
        
        if (xrCamera) {
          G.setEyeLevelY(xrCamera.globalPosition.y);
          G.setCameraForward(xrCamera.getForwardRay().direction);
        }

        let lJointsXR = leftHand ? extractHandJoints(leftHand) : null;
        let rJointsXR = rightHand ? extractHandJoints(rightHand) : null;

        if (this.inputManager.getSimulator().isActive()) {
          lJointsXR = null; rJointsXR = null;
        }

        if (lJointsXR) G.updateHandJoints("left", lJointsXR);
        if (rJointsXR) G.updateHandJoints("right", rJointsXR);

        const lJointsActual = G.getLeftHandJoints();
        const rJointsActual = G.getRightHandJoints();

        if (lJointsActual && rJointsActual) {
          this.playerController.processGestures(xrCamera?.getForwardRay().direction || this.engineManager.getCamera().getForwardRay().direction);
        }

        const gesture = G.getCurrentGesture();
        const apiSource = leftHand || rightHand ? "onHandAdded" : "waiting...";

        this.debugOverlay?.update({
          handTrackingActive: !!(lJointsActual || rJointsActual),
          leftJoints: lJointsActual,
          rightJoints: rJointsActual,
          gesture,
          handApiSource: apiSource,
        });

        this.vrHud?.updateHandTrackingDebug(!!leftHand, !!rightHand, lJointsActual, rJointsActual, gesture, apiSource);
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
