import {
  Engine,
  Scene,
  FreeCamera,
  Vector3,
  HemisphericLight,
  DirectionalLight,
  Color3,
  Color4,
  MeshBuilder,
  StandardMaterial,
  ParticleSystem,
  Texture,
  Animation,
  ActionManager,
  ExecuteCodeAction,
  WebXRFeatureName,
} from "@babylonjs/core";
import { HUD } from "./HUD";
import { CombatSystem } from "./CombatSystem";
import { VFXManager } from "./VFXManager";
import { GestureRecognizer } from "./GestureRecognizer";

export class Game {
  private engine: Engine;
  private scene: Scene;
  private camera!: FreeCamera;
  private hud!: HUD;
  private combat!: CombatSystem;
  private vfx!: VFXManager;
  private gestureRecognizer!: GestureRecognizer;
  private xr: any = null;
  private started = false;

  constructor(private canvas: HTMLCanvasElement) {
    this.engine = new Engine(canvas, true, {
      preserveDrawingBuffer: true,
      stencil: true,
    });
    this.scene = new Scene(this.engine);
    this.scene.clearColor = new Color4(0.02, 0.02, 0.08, 1);
  }

  start(): void {
    this.setupCamera();
    this.setupLights();
    this.setupEnvironment();

    this.vfx = new VFXManager(this.scene);
    this.combat = new CombatSystem(this.scene, this.vfx);
    this.gestureRecognizer = new GestureRecognizer(this.scene);
    this.hud = new HUD(this.canvas.parentElement!, this.combat);

    this.setupKeyboard();
    this.initWebXR();
    this.started = true;
    this.hud.show();
    this.canvas.focus();

    this.engine.runRenderLoop(() => {
      this.scene.render();
    });

    window.addEventListener("resize", () => {
      this.engine.resize();
    });
  }

  private setupCamera(): void {
    this.camera = new FreeCamera("camera", new Vector3(0, 1.7, 0), this.scene);
    this.camera.setTarget(new Vector3(0, 1.7, 10));
    this.camera.minZ = 0.1;
  }

  private setupLights(): void {
    const ambient = new HemisphericLight("ambient", new Vector3(0, 1, 0), this.scene);
    ambient.intensity = 0.4;
    ambient.diffuse = new Color3(0.4, 0.5, 0.8);
    ambient.groundColor = new Color3(0.1, 0.1, 0.2);

    const sun = new DirectionalLight("sun", new Vector3(-1, -2, 3), this.scene);
    sun.intensity = 0.8;
    sun.diffuse = new Color3(0.9, 0.85, 1.0);
  }

  private setupEnvironment(): void {
    // Suelo
    const ground = MeshBuilder.CreateGround("ground", { width: 200, height: 200 }, this.scene);
    const groundMat = new StandardMaterial("groundMat", this.scene);
    groundMat.diffuseColor = new Color3(0.05, 0.05, 0.12);
    groundMat.specularColor = new Color3(0.1, 0.1, 0.2);
    ground.material = groundMat;

    // Enemigo
    const enemy = MeshBuilder.CreateCapsule("enemy", { height: 1.8, radius: 0.3 }, this.scene);
    enemy.position = new Vector3(0, 0.9, 18);
    const enemyMat = new StandardMaterial("enemyMat", this.scene);
    enemyMat.diffuseColor = new Color3(0.8, 0.1, 0.1);
    enemyMat.emissiveColor = new Color3(0.3, 0.0, 0.0);
    enemy.material = enemyMat;

    // Aura del enemigo
    const aura = new ParticleSystem("enemyAura", 200, this.scene);
    aura.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    aura.emitter = enemy;
    aura.minEmitBox = new Vector3(-0.3, -0.9, -0.3);
    aura.maxEmitBox = new Vector3(0.3, 0.9, 0.3);
    aura.color1 = new Color4(1, 0.2, 0.2, 0.6);
    aura.color2 = new Color4(1, 0.5, 0.0, 0.3);
    aura.minSize = 0.05;
    aura.maxSize = 0.2;
    aura.minLifeTime = 0.3;
    aura.maxLifeTime = 0.8;
    aura.emitRate = 80;
    aura.minEmitPower = 0.5;
    aura.maxEmitPower = 1.5;
    aura.updateSpeed = 0.02;
    aura.start();

    // Manos del jugador (visibles en primera persona)
    this.createPlayerHands();
  }

  private createPlayerHands(): void {
    // Mano izquierda
    const leftHand = MeshBuilder.CreateBox("leftHand", { width: 0.12, height: 0.08, depth: 0.18 }, this.scene);
    leftHand.position = new Vector3(-0.35, 1.3, 0.6);
    leftHand.rotation = new Vector3(0.3, 0.1, 0.1);
    const handMat = new StandardMaterial("handMat", this.scene);
    handMat.diffuseColor = new Color3(0.85, 0.7, 0.6);
    leftHand.material = handMat;

    // Mano derecha
    const rightHand = MeshBuilder.CreateBox("rightHand", { width: 0.12, height: 0.08, depth: 0.18 }, this.scene);
    rightHand.position = new Vector3(0.35, 1.3, 0.6);
    rightHand.rotation = new Vector3(0.3, -0.1, -0.1);
    rightHand.material = handMat;

    // Animacion sutil de respiracion
    const breathAnim = new Animation("breath", "position.y", 30, Animation.ANIMATIONTYPE_FLOAT, Animation.ANIMATIONLOOPMODE_CYCLE);
    breathAnim.setKeys([
      { frame: 0, value: 1.3 },
      { frame: 45, value: 1.28 },
      { frame: 90, value: 1.3 },
    ]);
    leftHand.animations = [breathAnim];
    rightHand.animations = [breathAnim];
    this.scene.beginAnimation(leftHand, 0, 90, true);
    this.scene.beginAnimation(rightHand, 0, 90, true);
  }

  private setupKeyboard(): void {
    // Controles de teclado (para testing sin VR)
    window.addEventListener("keydown", (e) => {
      if (!this.started) return;
      switch (e.key.toLowerCase()) {
        case "a": this.combat.launchBasicAttack(); break;
        case "w": 
          if (this.combat.isInChargingState()) {
            this.combat.releaseChargedAttack();
          } else {
            this.combat.startChargedAttack();
          }
          break;
        case "s": this.combat.activateBlock(); break;
        case "d": this.combat.activateDodge(); break;
        case "r": this.combat.rechargeKi(); break;
        case "1": this.combat.kamehamehaStep(1); break;
        case "2": this.combat.finalFlashStep(1); break;
        case "v": this.enterVR(); break;
      }
    });
  }

  private async enterVR(): Promise<void> {
    if (this.xr) {
      await this.xr.baseExperience.enterXRAsync(
        'immersive-vr',
        'local'
      );
    }
  }

  private async initWebXR(): Promise<void> {
    try {
      const featureManager = this.scene.createDefaultXRExperienceAsync({
        uiOptions: {
          sessionMode: 'immersive-vr',
          referenceSpaceType: 'local-floor',
        },
        optionalFeatures: true,
      });

      this.xr = await featureManager;
      
      // Habilitar hand tracking
      const handTracking = this.xr.baseExperience.featuresManager.enableFeature(
        WebXRFeatureName.HAND_TRACKING,
        'latest'
      );

      // Loop de actualización de hand tracking
      this.scene.registerBeforeRender(() => {
        if (handTracking && handTracking.hands) {
          const leftHand = handTracking.hands.get('left');
          const rightHand = handTracking.hands.get('right');
          
          if (leftHand) {
            this.gestureRecognizer.updateHandJoints('left', this.extractJoints(leftHand));
          }
          if (rightHand) {
            this.gestureRecognizer.updateHandJoints('right', this.extractJoints(rightHand));
          }

          // Ejecutar acciones basadas en gestos
          this.processGestures();
        }
      });

      console.log("✅ WebXR + Hand Tracking inicializado");
    } catch (e) {
      console.log("ℹ️ WebXR no disponible:", e);
    }
  }

  private extractJoints(hand: any): any {
    const joints: any = {};
    try {
      if (hand.joints) {
        joints.wrist = this.getJointPos(hand.joints[0]);
        joints.indexTip = this.getJointPos(hand.joints[8]);
        joints.middleTip = this.getJointPos(hand.joints[12]);
        joints.ringTip = this.getJointPos(hand.joints[16]);
        joints.littleTip = this.getJointPos(hand.joints[20]);
        joints.thumbTip = this.getJointPos(hand.joints[4]);
      }
    } catch (e) {}
    return joints;
  }

  private getJointPos(joint: any): { x: number; y: number; z: number } {
    if (joint && joint.position) {
      return { x: joint.position.x, y: joint.position.y, z: joint.position.z };
    }
    return { x: 0, y: 0, z: 0 };
  }

  private processGestures(): void {
    const gesture = this.gestureRecognizer.getCurrentGesture();
    
    switch (gesture) {
      case 'ATTACKING':
        if (!this.combat.isInChargingState()) {
          this.combat.launchBasicAttack();
        }
        break;
      case 'CHARGING':
        this.combat.startChargedAttack();
        break;
      case 'BLOCKING':
        this.combat.activateBlock();
        break;
      case 'RECHARGING':
        this.combat.rechargeKi();
        break;
    }
  }

  dispose(): void {
    this.engine.dispose();
  }
}
