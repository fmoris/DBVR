import {
  Scene,
  WebXRFeatureName,
  WebXRDefaultExperience,
  WebXRHandTracking,
  WebXRHandJoint,
  WebXRHand,
  Vector3,
  Engine,
  Quaternion
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
  private lastSimulatedPower: string | null = null; // Seguimiento para evitar reinicios constantes del SIM


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

        // Horizon Lock: Project forward and right vectors onto the XZ plane to keep body orientation stable
        // regardless of head pitch (tilt up/down).
        const forwardWorld = xrCamera.getDirection(Vector3.Forward());
        const headForward = new Vector3(forwardWorld.x, 0, forwardWorld.z).normalize();
        
        // Fallback if orientation is undefined (looking perfectly up/down)
        if (headForward.length() < 0.001) {
            headForward.copyFromFloats(0, 0, 1);
        }

        const headRight = Vector3.Cross(Vector3.Up(), headForward).normalize();

        const ctx: XRHandsContext = {
            leftWrist: leftHand?.getJointMesh(WebXRHandJoint.WRIST),
            rightWrist: rightHand?.getJointMesh(WebXRHandJoint.WRIST),
            leftHand: leftHand || undefined,
            rightHand: rightHand || undefined,
            headPos: xrCamera.globalPosition,
            headForward,
            headRight,
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
                
                const sim = this.vrHud.getSimulator();
                const ikTargets = this.envManager.getIkTargets();
                
                // Vincular los blancos IK del Dude al simulador si existen y aún no están vinculados
                if (ikTargets && sim && !sim.customTargets) {
                    const eRoot = this.envManager.getEnemyRoot();
                    if (eRoot) {
                        sim.setExternalTargets(
                            ikTargets, 
                            eRoot.position, 
                            eRoot.rotationQuaternion ? eRoot.rotationQuaternion.toEulerAngles().y : eRoot.rotation.y
                        );
                    } else {
                        sim.setExternalTargets(ikTargets);
                    }
                }
                
                // Lógica del Simulador
                const isSimulating = this.vrHud.isSimulating();
                const targetPower = this.vrHud.targetPowerId();

                if (isSimulating) {
                    // Si estamos simulando, NO enviamos datos de tracking al espejo
                    // El simulador ya debería estar moviendo los blancos IK
                    if (!this.lastSimulatedPower && targetPower) {
                        this.lastSimulatedPower = targetPower;
                        console.log(`[XR] Modo Simulación ACTIVO para: ${this.lastSimulatedPower}`);
                    }
                } else {
                    if (this.lastSimulatedPower) {
                        console.log("[XR] Modo Simulación DETENIDO.");
                        this.lastSimulatedPower = null;
                    }
                    
                    // Si NO hay simulación activa, usamos el espejo normal (IK tracking del jugador)
                    this.envManager.updateEnemyMirror(
                        true, // Siempre activo para entrenar!
                        headPos,
                        headRot,
                        ctx.leftWrist.absolutePosition.clone(),
                        ctx.rightWrist.absolutePosition.clone()
                    );
                }

                const pRoot = this.envManager.getPlayerRoot();
                if (pRoot) {
                    pRoot.position.copyFrom(headPos);
                    // Ajustar la altura visual: el origen del modelo suele estar en los pies.
                    // Asumimos un offset estandar de -1.55m desde la cámara al piso para el avatar Goku.
                    pRoot.position.y -= 1.55;

                    // Rotación Lazy: el cuerpo gira sólo si tuerces mucho el cuello
                    const currentEuler = pRoot.rotationQuaternion ? pRoot.rotationQuaternion.toEulerAngles() : Vector3.Zero();
                    let bodyYaw = currentEuler.y;
                    const headYaw = headRot.toEulerAngles().y;
                    
                    let diff = headYaw - bodyYaw;
                    while (diff > Math.PI) diff -= Math.PI * 2;
                    while (diff < -Math.PI) diff += Math.PI * 2;

                    const deadzone = 0.8; // ~45 grados
                    if (Math.abs(diff) > deadzone) {
                        const targetYaw = bodyYaw + (diff > 0 ? (diff - deadzone) : (diff + deadzone));
                        bodyYaw += (targetYaw - bodyYaw) * 0.15; // Smooth Catch-up
                    }

                    pRoot.rotationQuaternion = Quaternion.RotationYawPitchRoll(bodyYaw, 0, 0); 
                }
            }
        }
      });
    }
  }

  public async enterVR(): Promise<void> {
    if (!this.xr) {
      throw new Error('[XRManager] El sistema WebXR no está inicializado. Llama a init() primero.');
    }
    
    // Asegurar que el audio se desbloquea en VR tras la interacción del usuario
    if (Engine.audioEngine) {
        Engine.audioEngine.unlock();
    }

    // IMPORTANTE: enterXRAsync debe ser llamado directamente en el stack de un evento de usuario.
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
