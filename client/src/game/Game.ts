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
} from "@babylonjs/core";
import { HUD } from "./HUD";
import { CombatSystem } from "./CombatSystem";
import { VFXManager } from "./VFXManager";

export class Game {
  private engine: Engine;
  private scene: Scene;
  private camera!: FreeCamera;
  private hud!: HUD;
  private combat!: CombatSystem;
  private vfx!: VFXManager;
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
    this.hud = new HUD(this.canvas.parentElement!, this.combat);

    this.setupKeyboard();
    this.showStartScreen();

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
    window.addEventListener("keydown", (e) => {
      if (!this.started) return;
      switch (e.key.toLowerCase()) {
        case "a": this.combat.launchAttack(); break;
        case "s": this.combat.activateBlock(); break;
        case "r": this.combat.rechargeKi(); break;
      }
    });
  }

  private showStartScreen(): void {
    const overlay = document.createElement("div");
    overlay.id = "start-screen";
    overlay.style.cssText = `
      position:absolute; inset:0; display:flex; flex-direction:column;
      align-items:center; justify-content:center;
      background:linear-gradient(180deg,#050510 0%,#0a0a2a 100%);
      z-index:20; gap:32px;
    `;

    overlay.innerHTML = `
      <div style="text-align:center">
        <h1 style="color:#00ccff;font-size:48px;font-family:'Courier New',monospace;
          font-weight:bold;letter-spacing:6px;
          text-shadow:0 0 30px rgba(0,200,255,0.8),0 0 60px rgba(0,100,255,0.4);
          margin:0;">VR KI COMBAT</h1>
        <p style="color:#4488aa;font-size:13px;font-family:'Courier New',monospace;
          letter-spacing:4px;margin-top:12px;text-transform:uppercase;">
          Sistema de combate accion-reaccion
        </p>
      </div>
      <div style="background:rgba(0,20,40,0.8);border:1px solid #0066aa;
        border-radius:8px;padding:24px 40px;text-align:center;max-width:360px;">
        <p style="color:#88bbcc;font-size:12px;font-family:'Courier New',monospace;
          line-height:2;letter-spacing:1px;">
          <span style="color:#00ff88">A</span> — Lanzar ataque de KI<br/>
          <span style="color:#00ff88">S</span> — Activar bloqueo<br/>
          <span style="color:#cc44ff">R</span> — Recargar energia KI
        </p>
      </div>
      <button id="start-btn" style="padding:14px 48px;
        background:linear-gradient(135deg,#003366,#0066cc);
        border:2px solid #0099ff;border-radius:6px;color:#00ccff;
        font-size:16px;font-family:'Courier New',monospace;font-weight:bold;
        letter-spacing:4px;cursor:pointer;text-transform:uppercase;
        box-shadow:0 0 20px rgba(0,150,255,0.5);">
        Iniciar Combate
      </button>
    `;

    this.canvas.parentElement!.appendChild(overlay);

    const btn = overlay.querySelector("#start-btn") as HTMLButtonElement;
    btn.addEventListener("click", () => {
      overlay.remove();
      this.started = true;
      this.hud.show();
      this.canvas.focus();
    });
  }

  dispose(): void {
    this.engine.dispose();
  }
}
