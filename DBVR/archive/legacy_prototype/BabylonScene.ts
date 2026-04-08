import * as BABYLON from "@babylonjs/core";
import { XRManager as WebXRManager } from "../../client/src/systems/xr/XRManager";

export interface GameState {
  playerKi: number;
  playerHealth: number;
  enemyKi: number;
  enemyHealth: number;
  combatState: "neutral" | "charging" | "attacking" | "defending" | "slowMotion" | "hit";
  isSlowMotion: boolean;
}

export type GameStateCallback = (state: GameState) => void;

export class BabylonScene {
  private engine: BABYLON.Engine;
  private scene: BABYLON.Scene;
  private camera: BABYLON.UniversalCamera;
  private enemyMesh: BABYLON.Mesh | null = null;
  private webXRManager: WebXRManager | null = null;

  // Estado del juego
  private state: GameState = {
    playerKi: 100,
    playerHealth: 100,
    enemyKi: 100,
    enemyHealth: 100,
    combatState: "neutral",
    isSlowMotion: false,
  };

  private onStateChange: GameStateCallback;
  private kiRegenRate = 5; // por segundo
  private slowMotionFactor = 0.3;
  private slowMotionTimeout: ReturnType<typeof setTimeout> | null = null;

  constructor(canvas: HTMLCanvasElement, onStateChange: GameStateCallback) {
    this.onStateChange = onStateChange;

    this.engine = new BABYLON.Engine(canvas, true, {
      preserveDrawingBuffer: true,
      stencil: true,
    });

    this.scene = new BABYLON.Scene(this.engine);
    this.scene.clearColor = new BABYLON.Color4(0.05, 0.05, 0.1, 1);

    this.camera = new BABYLON.UniversalCamera(
      "camera",
      new BABYLON.Vector3(0, 1.6, 0),
      this.scene
    );
    this.camera.setTarget(new BABYLON.Vector3(0, 1.6, 10));

    this.setupLights();
    this.setupEnvironment();
    this.setupEnemy();
    this.setupKeyboardControls();
    this.initializeWebXR();

    this.engine.runRenderLoop(() => {
      const delta = this.engine.getDeltaTime() / 1000;
      this.update(delta);
      this.scene.render();
    });

    window.addEventListener("resize", () => this.engine.resize());
  }

  // ─── Setup ────────────────────────────────────────────────────────────────

  private async initializeWebXR(): Promise<void> {
    try {
      this.webXRManager = new WebXRManager({ scene: this.scene } as any);
      const success = await this.webXRManager.init();
      
      if (success) {
        console.log("✅ WebXR disponible - Botón VR aparecerá automáticamente");
      }
    } catch (error) {
      console.warn("⚠️ WebXR no disponible:", error);
    }
  }

  private setupLights(): void {
    const hemi = new BABYLON.HemisphericLight(
      "hemi",
      new BABYLON.Vector3(0, 1, 0),
      this.scene
    );
    hemi.intensity = 0.6;
    hemi.diffuse = new BABYLON.Color3(0.8, 0.9, 1.0);

    const dir = new BABYLON.DirectionalLight(
      "dir",
      new BABYLON.Vector3(-1, -2, -1),
      this.scene
    );
    dir.intensity = 0.8;
    dir.diffuse = new BABYLON.Color3(1, 0.95, 0.8);
  }

  private setupEnvironment(): void {
    // Skybox
    const skybox = BABYLON.MeshBuilder.CreateBox("skybox", { size: 1000 }, this.scene);
    const skyMat = new BABYLON.StandardMaterial("skyMat", this.scene);
    skyMat.emissiveColor = new BABYLON.Color3(0.05, 0.08, 0.2);
    skyMat.backFaceCulling = false;
    skybox.material = skyMat;
    skybox.infiniteDistance = true;

    // Suelo
    const ground = BABYLON.MeshBuilder.CreateGround(
      "ground",
      { width: 200, height: 200 },
      this.scene
    );
    const groundMat = new BABYLON.StandardMaterial("groundMat", this.scene);
    groundMat.diffuseColor = new BABYLON.Color3(0.15, 0.15, 0.2);
    groundMat.specularColor = new BABYLON.Color3(0.05, 0.05, 0.1);
    ground.material = groundMat;
    ground.position.y = -1.6;
  }

  private setupEnemy(): void {
    // Cuerpo del enemigo
    this.enemyMesh = BABYLON.MeshBuilder.CreateCylinder(
      "enemy",
      { height: 1.8, diameterTop: 0.5, diameterBottom: 0.5, tessellation: 12 },
      this.scene
    );
    this.enemyMesh.position = new BABYLON.Vector3(0, 0.3, 15);

    const enemyMat = new BABYLON.StandardMaterial("enemyMat", this.scene);
    enemyMat.diffuseColor = new BABYLON.Color3(0.6, 0.1, 0.1);
    enemyMat.emissiveColor = new BABYLON.Color3(0.2, 0.0, 0.0);
    this.enemyMesh.material = enemyMat;

    // Cabeza
    const head = BABYLON.MeshBuilder.CreateSphere(
      "enemyHead",
      { diameter: 0.5 },
      this.scene
    );
    head.position = new BABYLON.Vector3(0, 1.25, 15);
    head.material = enemyMat;

    // Aura del enemigo
    this.createAura(this.enemyMesh, new BABYLON.Color3(1, 0.2, 0.2));
  }

  private createAura(parent: BABYLON.Mesh, color: BABYLON.Color3): void {
    const ps = new BABYLON.ParticleSystem("aura", 200, this.scene);
    ps.emitter = parent;
    ps.minEmitBox = new BABYLON.Vector3(-0.3, -0.9, -0.3);
    ps.maxEmitBox = new BABYLON.Vector3(0.3, 0.9, 0.3);
    ps.color1 = new BABYLON.Color4(color.r, color.g, color.b, 0.5);
    ps.color2 = new BABYLON.Color4(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.1);
    ps.colorDead = new BABYLON.Color4(0, 0, 0, 0);
    ps.minSize = 0.05;
    ps.maxSize = 0.15;
    ps.minLifeTime = 0.3;
    ps.maxLifeTime = 0.8;
    ps.emitRate = 80;
    ps.blendMode = BABYLON.ParticleSystem.BLENDMODE_ADD;
    ps.gravity = new BABYLON.Vector3(0, 2, 0);
    ps.direction1 = new BABYLON.Vector3(-0.5, 1, -0.5);
    ps.direction2 = new BABYLON.Vector3(0.5, 2, 0.5);
    ps.minAngularSpeed = 0;
    ps.maxAngularSpeed = Math.PI;
    ps.minEmitPower = 0.5;
    ps.maxEmitPower = 1.5;
    ps.updateSpeed = 0.02;
    ps.start();
  }

  private setupKeyboardControls(): void {
    window.addEventListener("keydown", (e) => {
      switch (e.key.toLowerCase()) {
        case "a":
          this.launchAttack();
          break;
        case "s":
          this.activateBlock();
          break;
        case "r":
          this.rechargeKi();
          break;
      }
    });
  }

  // ─── Acciones de combate ──────────────────────────────────────────────────

  launchAttack(): void {
    if (this.state.playerKi < 20) return;
    if (this.state.combatState === "attacking") return;

    this.state.playerKi = Math.max(0, this.state.playerKi - 20);
    this.state.combatState = "attacking";
    this.activateSlowMotion();
    this.spawnProjectile();
    this.notifyState();
  }

  activateBlock(): void {
    if (this.state.playerKi < 10) return;
    this.state.playerKi = Math.max(0, this.state.playerKi - 10);
    this.state.combatState = "defending";
    this.notifyState();

    setTimeout(() => {
      if (this.state.combatState === "defending") {
        this.state.combatState = "neutral";
        this.notifyState();
      }
    }, 1500);
  }

  rechargeKi(): void {
    this.state.playerKi = Math.min(100, this.state.playerKi + 30);
    this.notifyState();
  }

  private activateSlowMotion(): void {
    this.state.isSlowMotion = true;
    this.scene.animationTimeScale = this.slowMotionFactor;

    if (this.slowMotionTimeout) clearTimeout(this.slowMotionTimeout);
    this.slowMotionTimeout = setTimeout(() => {
      this.state.isSlowMotion = false;
      this.scene.animationTimeScale = 1;
      if (this.state.combatState === "attacking") {
        this.state.combatState = "neutral";
      }
      this.notifyState();
    }, 2000);
  }

  private spawnProjectile(): void {
    const projectile = BABYLON.MeshBuilder.CreateSphere(
      `proj_${Date.now()}`,
      { diameter: 0.5, segments: 10 },
      this.scene
    );
    projectile.position = new BABYLON.Vector3(0, 1.2, 1.5);

    const mat = new BABYLON.StandardMaterial(`projMat_${Date.now()}`, this.scene);
    mat.emissiveColor = new BABYLON.Color3(0.2, 0.7, 1.0);
    mat.diffuseColor = new BABYLON.Color3(0, 0.5, 1.0);
    projectile.material = mat;

    // Partículas del proyectil
    const ps = new BABYLON.ParticleSystem("projPs", 100, this.scene);
    ps.emitter = projectile;
    ps.color1 = new BABYLON.Color4(0.2, 0.8, 1, 0.8);
    ps.color2 = new BABYLON.Color4(0, 0.4, 1, 0.4);
    ps.colorDead = new BABYLON.Color4(0, 0, 0.5, 0);
    ps.minSize = 0.03;
    ps.maxSize = 0.1;
    ps.minLifeTime = 0.1;
    ps.maxLifeTime = 0.3;
    ps.emitRate = 150;
    ps.blendMode = BABYLON.ParticleSystem.BLENDMODE_ADD;
    ps.gravity = new BABYLON.Vector3(0, 0, 0);
    ps.direction1 = new BABYLON.Vector3(-1, -1, -1);
    ps.direction2 = new BABYLON.Vector3(1, 1, 1);
    ps.minEmitPower = 0.5;
    ps.maxEmitPower = 1;
    ps.updateSpeed = 0.02;
    ps.start();

    // Animacion de vuelo
    const anim = new BABYLON.Animation(
      "projAnim",
      "position.z",
      60,
      BABYLON.Animation.ANIMATIONTYPE_FLOAT,
      BABYLON.Animation.ANIMATIONLOOPMODE_CONSTANT
    );
    anim.setKeys([
      { frame: 0, value: 1.5 },
      { frame: 60, value: 20 },
    ]);

    const ease = new BABYLON.CubicEase();
    ease.setEasingMode(BABYLON.EasingFunction.EASINGMODE_EASEIN);
    anim.setEasingFunction(ease);

    projectile.animations = [anim];
    this.scene.beginAnimation(projectile, 0, 60, false, 1, () => {
      // Impacto
      if (this.enemyMesh) {
        this.createImpactEffect(this.enemyMesh.position.clone());
        this.state.enemyHealth = Math.max(0, this.state.enemyHealth - 15);
        this.notifyState();
      }
      ps.stop();
      setTimeout(() => {
        ps.dispose();
        projectile.dispose();
      }, 500);
    });
  }

  private createImpactEffect(position: BABYLON.Vector3): void {
    const ps = new BABYLON.ParticleSystem("impact", 300, this.scene);
    ps.emitter = position;
    ps.color1 = new BABYLON.Color4(1, 0.8, 0.2, 1);
    ps.color2 = new BABYLON.Color4(1, 0.3, 0, 0.8);
    ps.colorDead = new BABYLON.Color4(0.5, 0, 0, 0);
    ps.minSize = 0.05;
    ps.maxSize = 0.3;
    ps.minLifeTime = 0.2;
    ps.maxLifeTime = 0.6;
    ps.emitRate = 500;
    ps.blendMode = BABYLON.ParticleSystem.BLENDMODE_ADD;
    ps.gravity = new BABYLON.Vector3(0, -5, 0);
    ps.direction1 = new BABYLON.Vector3(-3, -3, -3);
    ps.direction2 = new BABYLON.Vector3(3, 3, 3);
    ps.minEmitPower = 2;
    ps.maxEmitPower = 6;
    ps.updateSpeed = 0.02;
    ps.manualEmitCount = 300;
    ps.start();
    setTimeout(() => ps.dispose(), 1000);
  }

  // ─── Loop de actualización ────────────────────────────────────────────────

  private update(delta: number): void {
    // Regenerar KI
    if (this.state.combatState !== "attacking") {
      this.state.playerKi = Math.min(100, this.state.playerKi + this.kiRegenRate * delta);
    }
    this.notifyState();
  }

  private notifyState(): void {
    this.onStateChange({ ...this.state });
  }

  // ─── API pública ──────────────────────────────────────────────────────────

  getState(): GameState {
    return { ...this.state };
  }

  dispose(): void {
    if (this.slowMotionTimeout) clearTimeout(this.slowMotionTimeout);
    this.engine.dispose();
  }
}
