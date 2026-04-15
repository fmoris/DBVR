import {
  Scene,
  WebXRFeatureName,
  WebXRDefaultExperience,
  WebXRHandTracking,
  WebXRHandJoint,
  WebXRHand,
  Vector3
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
  private gestureSocket: WebSocket | null = null;


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
        uiOptions: { 
            sessionMode: "immersive-vr", 
            referenceSpaceType: "local-floor" 
        },
        optionalFeatures: ["hand-tracking", "dom-overlay"],
        domOverlay: { element: this.xrOverlay },
        inputOptions: {
            doNotLoadControllerMeshes: true
        }
      };
      
      this.xr = await this.scene.createDefaultXRExperienceAsync(xrConfig);
      if (!this.xr) {
          throw new Error("No se pudo crear la experiencia WebXR predeterminada.");
      }

      this.inputManager.getGSS().setXRExperience(this.xr);
      this.setupXRExperience();
      this.setupHandTracking();
      console.log("[XRManager] WebXR inicializado correctamente");
      return true;
    } catch (e: any) {
      console.warn("[XRManager] Error al inicializar WebXR:", e);
      // Notificar al HUD si es posible
      const msg = e.message || String(e);
      window.dispatchEvent(new CustomEvent('xr-init-error', { detail: { message: msg } }));
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
      this.setupGestureStreaming();

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
            headForward: xrCamera.getDirection(Vector3.Forward()),
            headRight: xrCamera.getDirection(Vector3.Right()),
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

        // NEW: Real-time joint streaming
        this.streamHandData(leftHand);
        this.streamHandData(rightHand);

        const now = performance.now();
        const graceActive = gss.currentState !== 'idle' && (now - gss.lastValidGestureTime) < gss.gracePeriodMs;
        const graceTimeLeft = graceActive ? Math.round(gss.gracePeriodMs - (now - gss.lastValidGestureTime)) : 0;

        this.debugOverlay?.update({
          handTrackingActive,
          leftJoints,
          rightJoints,
          gesture: currentGesture,
          handApiSource: leftHand || rightHand ? "WebXR Hands" : "waiting...",
          graceActive,
          graceTimeLeft
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
    if (!this.xr) {
      throw new Error('[XRManager] El sistema WebXR no está inicializado. Llama a init() primero.');
    }
    
    // IMPORTANTE: enterXRAsync debe ser llamado directamente en el stack de un evento de usuario.
    // No usar polling (setInterval) aquí ya que rompe la activación de usuario.
    await this.xr.baseExperience.enterXRAsync('immersive-vr', 'local-floor');
  }

  public getXR(): WebXRDefaultExperience | null {
    return this.xr;
  }

  public async exitXR(): Promise<void> {
    if (this.xr?.baseExperience?.state === 2) {
      await this.xr.baseExperience.exitXRAsync();
    }
    if (this.gestureSocket) {
      this.gestureSocket.close();
      this.gestureSocket = null;
    }
  }

  private setupGestureStreaming(): void {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const host = window.location.hostname; // Solo el nombre/IP
    const url = `${protocol}//${host}:8080`;

    console.log(`[XRManager] 📡 Connecting to secure isolated gesture capture: ${url}`);
    this.gestureSocket = new WebSocket(url);

    this.gestureSocket.onopen = () => console.log('[XRManager] ✅ Secure gesture stream connected');
    this.gestureSocket.onerror = (e) => console.warn('[XRManager] ❌ Secure gesture stream error:', e);
  }

  private streamHandData(hand: WebXRHand | null): void {
    if (!hand || !this.gestureSocket || this.gestureSocket.readyState !== WebSocket.OPEN) return;

    const keyJoints = [
      WebXRHandJoint.WRIST,
      WebXRHandJoint.INDEX_FINGER_TIP,
      WebXRHandJoint.MIDDLE_FINGER_TIP,
      WebXRHandJoint.RING_FINGER_TIP,
      WebXRHandJoint.THUMB_TIP
    ];

    const joints: Record<string, number[]> = {};
    let found = false;

    keyJoints.forEach(jId => {
      const mesh = hand.getJointMesh(jId);
      if (mesh) {
        joints[jId] = [
          mesh.absolutePosition.x,
          mesh.absolutePosition.y,
          mesh.absolutePosition.z
        ];
        found = true;
      }
    });

    if (found) {
      const handedness = (hand as any).handedness || (hand as any).xrController?.inputSource?.handedness;
      this.gestureSocket.send(JSON.stringify({
        hand: handedness,
        joints,
        timestamp: performance.now()
      }));
    }
  }
}
