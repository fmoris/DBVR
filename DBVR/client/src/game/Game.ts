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
  Mesh,
  StandardMaterial,
  ParticleSystem,
  Texture,
  Animation,
  WebXRFeatureName,
  SceneLoader
} from "@babylonjs/core";
import "@babylonjs/loaders/glTF";
import { HUD } from "./HUD";
import { CombatSystem } from "./CombatSystem";
import { VFXManager } from "./VFXManager";
import { GestureRecognizer, extractHandJoints } from "./GestureRecognizer";
import { GestureDebugOverlay } from "./GestureDebugOverlay";
import { VoiceRecognizer } from "./VoiceRecognizer";
import { ResultScreen } from "./ResultScreen";
import { VRHud } from "./VRHud";
import { GestureSimulator } from "./GestureSimulator";
import gokuConfig from "../models/goku.json";
import vegetaConfig from "../models/vegeta.json";

// Importación estática de Vite de los modelos GLB
// @ts-ignore
import gokuBaseUrl from "../models/goku/goku_base.glb?url";
// @ts-ignore
import vegetaBaseUrl from "../models/vegeta/vegeta_base.glb?url";

const MODEL_URLS: Record<string, string> = {
  "goku/goku_base.glb": gokuBaseUrl,
  "vegeta/vegeta_base.glb": vegetaBaseUrl,
};

export class Game {
  private engine: Engine;
  private scene: Scene;
  private camera!: FreeCamera;
  private hud!: HUD;
  private combat!: CombatSystem;
  private vfx!: VFXManager;
  private gestureRecognizer!: GestureRecognizer;
  private voiceRecognizer!: VoiceRecognizer;
  private resultScreen!: ResultScreen;
  private combatStartTime = 0;
  private lastKiBlastTime: number = 0;
  private leftChargePower: number = 1.0;
  private rightChargePower: number = 1.0; 
  private leftChargeStartKi: number = 0;
  private rightChargeStartKi: number = 0;
  private lastChargeUpdateTime: number = 0;
  private lastChargedFireTime: number = 0; // Grace period para evitar doble disparo
  private playerAura: ParticleSystem | null = null;
  private enemyAura: ParticleSystem | null = null;
  private xr: any = null;
  private started = false;
  private menuCallback: (() => void) | null = null;
  private debugOverlay!: GestureDebugOverlay;
  private handTrackingActive = false;
  private vrHud!: VRHud;
  private simulator!: GestureSimulator;
  private leftPalmMesh?: Mesh;
  private rightPalmMesh?: Mesh;
  private lastReportedGesture: string = "IDLE";

  constructor(
    private canvas: HTMLCanvasElement,
    private xrOverlay: HTMLElement = canvas.parentElement!
  ) {
    this.engine = new Engine(canvas, true, {
      preserveDrawingBuffer: true,
      stencil: true,
    });
    this.scene = new Scene(this.engine);
    this.scene.clearColor = new Color4(0.02, 0.02, 0.08, 1);
  }

  /** Registrar callback para volver al menú principal (llamado desde main.ts) */
  setMenuCallback(cb: () => void): void {
    this.menuCallback = cb;
  }

  start(): void {
    this.setupCamera();
    this.setupLights();
    
    // Inicializar Managers antes del entorno (porque el entorno usa VFX/Auras)
    this.vfx = new VFXManager(this.scene);
    this.combat = new CombatSystem(this.scene, this.vfx, gokuConfig, vegetaConfig);
    this.gestureRecognizer = new GestureRecognizer(this.scene);
    this.voiceRecognizer = new VoiceRecognizer();

    // Sincronizar poderes iniciales (Goku Base) desde powers.json
    const initialPowers = gokuConfig.transformations?.[0]?.powers || [];
    this.combat.setAvailablePowers(initialPowers);
    this.voiceRecognizer.setAllowedPowers(initialPowers);
    this.gestureRecognizer.setAllowedPowers(initialPowers);

    this.setupEnvironment();

    // VRHud: HUD 3D world-space para Meta Quest 3
    // Se crea aquí pero se adjunta a la cámara XR en initWebXR()
    this.vrHud = new VRHud(this.scene, this.combat);
    // Montar HUD, ResultScreen y DebugOverlay en el xrOverlay
    // para que sean visibles dentro del visor XR via dom-overlay
    this.hud = new HUD(this.xrOverlay, this.combat);
    this.resultScreen = new ResultScreen(this.xrOverlay);
    this.debugOverlay = new GestureDebugOverlay(this.xrOverlay, this.scene);
    this.simulator = new GestureSimulator(this.gestureRecognizer);

    // Conectar botón Menú del HUD
    this.hud.onMenu(() => {
      if (this.menuCallback) this.menuCallback();
    });

    // Conectar botón DBG del HUD al overlay de debug
    this.hud.onDebugToggle(() => this.debugOverlay.toggle());

    this.setupKeyboard();
    this.setupVoiceRecognition();
    this.setupGameOverHandler();
    this.initWebXR();
    this.started = true;
    this.combatStartTime = Date.now();
    this.playerAura = this.vfx.createAura("player_aura", this.camera.position);
    this.hud.show();
    this.canvas.focus();

    this.engine.runRenderLoop(() => {
      this.scene.render();
    });

    // Sincronizar mallas de manos con el GestureRecognizer (para Simulación y XR)
    this.scene.registerBeforeRender(() => {
      this.syncHandMeshes();
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
    // Luz ambiental: tono calido de atardecer
    const ambient = new HemisphericLight("ambient", new Vector3(0, 1, 0), this.scene);
    ambient.intensity = 0.55;
    ambient.diffuse = new Color3(0.85, 0.65, 0.45);   // naranja calido
    ambient.groundColor = new Color3(0.25, 0.15, 0.08); // tierra oscura
    ambient.specular = new Color3(0.2, 0.15, 0.1);

    // Sol bajo (atardecer lateral)
    const sun = new DirectionalLight("sun", new Vector3(-0.6, -1.2, 1.0), this.scene);
    sun.intensity = 1.1;
    sun.diffuse = new Color3(1.0, 0.72, 0.38);  // dorado-naranja
    sun.specular = new Color3(1.0, 0.6, 0.2);

    // Luz de relleno azulada (cielo)
    const fill = new HemisphericLight("fill", new Vector3(0, -1, 0), this.scene);
    fill.intensity = 0.25;
    fill.diffuse = new Color3(0.3, 0.45, 0.7);
    fill.groundColor = new Color3(0.1, 0.08, 0.05);
  }

  private setupEnvironment(): void {
    // Cielo: gradiente de atardecer (fondo de la escena)
    this.scene.clearColor = new Color4(0.55, 0.38, 0.22, 1); // naranja-dorado

    // Suelo: tierra/roca de canon
    const ground = MeshBuilder.CreateGround("ground", { width: 300, height: 300, subdivisions: 8 }, this.scene);
    const groundMat = new StandardMaterial("groundMat", this.scene);
    groundMat.diffuseColor = new Color3(0.32, 0.22, 0.14);  // tierra rojiza
    groundMat.specularColor = new Color3(0.05, 0.04, 0.03);
    groundMat.ambientColor = new Color3(0.15, 0.10, 0.06);
    ground.material = groundMat;

    // Formaciones rocosas de fondo (canon)
    this.createCanyonRocks();

    // Enemigo (Vegeta)
    const enemy = MeshBuilder.CreateCapsule("enemy", { height: 1.8, radius: 0.3 }, this.scene);
    enemy.position = new Vector3(0, 0.9, 18);
    const enemyMat = new StandardMaterial("enemyMat", this.scene);
    enemyMat.diffuseColor = Color3.FromHexString("#1e1b4b");
    enemyMat.emissiveColor = new Color3(0.0, 0.0, 0.2);
    enemy.material = enemyMat;
    
    // Attempt dynamic 3D Model loading via Vite static url parsing
    const tryUrl = vegetaConfig.transformations?.[0]?.url;
    if (tryUrl && MODEL_URLS[tryUrl]) {
      SceneLoader.ImportMeshAsync("", MODEL_URLS[tryUrl], "", this.scene).then((result) => {
         enemy.isVisible = false; // Hide fallback capsule
         const root = result.meshes[0];
         const bInfo = root.getHierarchyBoundingVectors();
         const height = bInfo.max.y - bInfo.min.y;
         if (height > 0.001) {
             const factor = 1.8 / height;
             root.scaling.scaleInPlace(factor);
         } else {
             root.scaling.scaleInPlace(100);
         }

         const spawnPos = Math.abs(enemy.position.z) > 0 ? enemy.position.clone() : new Vector3(0, 0.9, 18);
         spawnPos.y -= 0.9; // El pivote de GLB suele estar en los pies (suelo)
         root.position = spawnPos;
         
         // Asegurar que mire al jugador
         root.rotationQuaternion = null;
         root.rotation.y = 0; // El modelo probablemente ya venía orientado hacia el frente
         
         console.log(`[GLB] Successfully loaded ${tryUrl} (height=${height.toFixed(3)})`);
      }).catch((e) => {
         console.warn(`[GLB] Missing model file ${tryUrl}, defaulting to collision capsule:`, e); 
      });
    }

    // Aura del enemigo (Vegeta) - Inicializada con la capsula base
    this.enemyAura = this.vfx.createAura("enemy_aura", enemy);
    
    // Manos del jugador (visibles en primera persona)
    this.createPlayerHands();
  }

  private createCanyonRocks(): void {
    // Columnas de roca a los lados y fondo para dar sensacion de canon
    const rockPositions = [
      // Fondo izquierdo
      { x: -30, y: 0, z: 60, w: 8, h: 28, d: 10 },
      { x: -20, y: 0, z: 70, w: 6, h: 22, d: 8 },
      { x: -40, y: 0, z: 50, w: 10, h: 35, d: 12 },
      // Fondo derecho
      { x: 30,  y: 0, z: 60, w: 8, h: 28, d: 10 },
      { x: 20,  y: 0, z: 70, w: 6, h: 22, d: 8 },
      { x: 40,  y: 0, z: 50, w: 10, h: 35, d: 12 },
      // Fondo centro
      { x: 0,   y: 0, z: 80, w: 20, h: 18, d: 15 },
      { x: -10, y: 0, z: 90, w: 12, h: 25, d: 10 },
      { x: 10,  y: 0, z: 90, w: 12, h: 25, d: 10 },
      // Laterales cercanos
      { x: -60, y: 0, z: 20, w: 15, h: 40, d: 20 },
      { x: 60,  y: 0, z: 20, w: 15, h: 40, d: 20 },
    ];

    const rockMat = new StandardMaterial("rockMat", this.scene);
    rockMat.diffuseColor = new Color3(0.38, 0.26, 0.16);
    rockMat.specularColor = new Color3(0.04, 0.03, 0.02);
    rockMat.ambientColor = new Color3(0.18, 0.12, 0.07);

    const rockMat2 = new StandardMaterial("rockMat2", this.scene);
    rockMat2.diffuseColor = new Color3(0.48, 0.32, 0.18);
    rockMat2.specularColor = new Color3(0.05, 0.04, 0.02);

    rockPositions.forEach((r, i) => {
      const rock = MeshBuilder.CreateBox(`rock${i}`, { width: r.w, height: r.h, depth: r.d }, this.scene);
      rock.position = new Vector3(r.x, r.h / 2 - 0.5, r.z);
      // Ligera rotacion aleatoria para naturalidad
      rock.rotation.y = (i * 0.37) % (Math.PI * 2);
      rock.material = i % 2 === 0 ? rockMat : rockMat2;
    });

    // Nubes: esferas semitransparentes en el horizonte
    const cloudMat = new StandardMaterial("cloudMat", this.scene);
    cloudMat.diffuseColor = new Color3(0.95, 0.75, 0.55);
    cloudMat.emissiveColor = new Color3(0.4, 0.25, 0.1);
    cloudMat.alpha = 0.35;

    const cloudPositions = [
      { x: -25, y: 22, z: 65, r: 8 },
      { x: -10, y: 26, z: 75, r: 10 },
      { x: 15,  y: 20, z: 68, r: 7 },
      { x: 30,  y: 24, z: 72, r: 9 },
      { x: 0,   y: 30, z: 85, r: 12 },
      { x: -35, y: 18, z: 55, r: 6 },
      { x: 40,  y: 19, z: 58, r: 7 },
    ];

    cloudPositions.forEach((c, i) => {
      const cloud = MeshBuilder.CreateSphere(`cloud${i}`, { diameter: c.r * 2, segments: 6 }, this.scene);
      cloud.position = new Vector3(c.x, c.y, c.z);
      cloud.scaling.y = 0.45; // aplanar para parecer nubes
      cloud.material = cloudMat;
    });
  }

  private createPlayerHands(): void {
    // Material de piel con tono calido
    const handMat = new StandardMaterial("handMat", this.scene);
    handMat.diffuseColor = new Color3(0.88, 0.72, 0.58);
    handMat.specularColor = new Color3(0.15, 0.1, 0.08);
    handMat.ambientColor = new Color3(0.3, 0.22, 0.15);

    // Mano izquierda — palma + dedos
    this.leftPalmMesh = MeshBuilder.CreateBox("leftHand", { width: 0.22, height: 0.06, depth: 0.28 }, this.scene);
    this.leftPalmMesh.position = new Vector3(-0.52, 1.12, 0.55);
    this.leftPalmMesh.rotation = new Vector3(-0.35, 0.12, 0.18);
    this.leftPalmMesh.material = handMat;

    // Dedos izquierda (4 cajas)
    for (let i = 0; i < 4; i++) {
      const finger = MeshBuilder.CreateBox(`lFinger${i}`, { width: 0.04, height: 0.04, depth: 0.14 }, this.scene);
      finger.parent = this.leftPalmMesh;
      finger.position = new Vector3(
        -0.07 + i * 0.05,
        -0.01,
        0.19
      );
      finger.rotation = new Vector3(0, 0, 0); // Local a la palma
      finger.material = handMat;
    }
    // Pulgar izquierdo
    const lThumb = MeshBuilder.CreateBox("lThumb", { width: 0.05, height: 0.04, depth: 0.10 }, this.scene);
    lThumb.parent = this.leftPalmMesh;
    lThumb.position = new Vector3(0.14, 0, 0.06);
    lThumb.rotation = new Vector3(-0.2, 0.5, 0.3);
    lThumb.material = handMat;

    // Mano derecha — palma + dedos
    this.rightPalmMesh = MeshBuilder.CreateBox("rightHand", { width: 0.22, height: 0.06, depth: 0.28 }, this.scene);
    this.rightPalmMesh.position = new Vector3(0.52, 1.12, 0.55);
    this.rightPalmMesh.rotation = new Vector3(-0.35, -0.12, -0.18);
    this.rightPalmMesh.material = handMat;

    for (let i = 0; i < 4; i++) {
      const finger = MeshBuilder.CreateBox(`rFinger${i}`, { width: 0.04, height: 0.04, depth: 0.14 }, this.scene);
      finger.parent = this.rightPalmMesh;
      finger.position = new Vector3(
        0.07 - i * 0.05,
        -0.01,
        0.19
      );
      finger.rotation = new Vector3(0, 0, 0); // Local a la palma
      finger.material = handMat;
    }
    const rThumb = MeshBuilder.CreateBox("rThumb", { width: 0.05, height: 0.04, depth: 0.10 }, this.scene);
    rThumb.parent = this.rightPalmMesh;
    rThumb.position = new Vector3(-0.14, 0, 0.06);
    rThumb.rotation = new Vector3(-0.2, -0.5, -0.3);
    rThumb.material = handMat;

    // Aura de KI azul alrededor de las manos
    const kiAura = new ParticleSystem("handAura", 120, this.scene);
    kiAura.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    kiAura.emitter = this.leftPalmMesh;
    kiAura.minEmitBox = new Vector3(-0.35, -0.05, -0.15);
    kiAura.maxEmitBox = new Vector3(0.35, 0.05, 0.15);
    kiAura.color1 = new Color4(0.2, 0.7, 1.0, 0.5);
    kiAura.color2 = new Color4(0.4, 0.9, 1.0, 0.2);
    kiAura.colorDead = new Color4(0.1, 0.3, 0.8, 0.0);
    kiAura.minSize = 0.03;
    kiAura.maxSize = 0.10;
    kiAura.minLifeTime = 0.2;
    kiAura.maxLifeTime = 0.5;
    kiAura.emitRate = 40;
    kiAura.minEmitPower = 0.1;
    kiAura.maxEmitPower = 0.4;
    kiAura.updateSpeed = 0.025;
    kiAura.gravity = new Vector3(0, 0.2, 0);
    kiAura.start();

    // Animacion de respiracion — manos bajan ligeramente
    const breathAnim = new Animation("breath", "position.y", 30,
      Animation.ANIMATIONTYPE_FLOAT, Animation.ANIMATIONLOOPMODE_CYCLE);
    breathAnim.setKeys([
      { frame: 0,  value: 1.12 },
      { frame: 50, value: 1.09 },
      { frame: 100, value: 1.12 },
    ]);
    this.leftPalmMesh.animations  = [breathAnim];
    this.rightPalmMesh.animations = [breathAnim];
    this.scene.beginAnimation(this.leftPalmMesh,  0, 100, true);
    this.scene.beginAnimation(this.rightPalmMesh, 0, 100, true);
  }

  private setupGameOverHandler(): void {
    // Registrar el callback UNA SOLA VEZ antes de que ocurra el game over
    // (no dentro de onGameOver, donde se acumulan por cada partida)
    this.resultScreen.onAction((action) => {
      if (action === "restart") {
        window.location.reload();
      } else if (action === "menu") {
        // Usar el flujo limpio de retorno al menú si está disponible
        if (this.menuCallback) {
          this.resultScreen.hide();
          this.menuCallback();
        } else {
          window.location.reload();
        }
      }
    });

    this.combat.onGameOver((winner) => {
      const stats = this.combat.getStats();
      const durationSeconds = (Date.now() - this.combatStartTime) / 1000;

      this.resultScreen.show({
        playerNP: stats.playerNP,
        enemyNP: stats.enemyNP,
        playerKi: stats.playerKi,
        winner,
        combatDurationSeconds: durationSeconds,
      });
    });
  }

  private setupVoiceRecognition(): void {
    if (!this.voiceRecognizer.isAvailable()) {
      console.log("[Voice] Web Speech API no disponible - comandos de voz desactivados");
      return;
    }

    this.voiceRecognizer.onCommand((command, transcript) => {
      if (!this.started || !command) return;
      console.log(`[Voice] Comando detectado: ${command} ("${transcript}")`);
      this.combat.triggerSpecial(command);
      this.combat.applyVoiceBonus(command);
    });

    this.voiceRecognizer.onStatus((_active, transcript) => {
      this.hud.showVoiceTranscript(transcript);
    });

    // Iniciar escucha automaticamente
    this.voiceRecognizer.start();
    console.log("[Voice] Reconocimiento de voz activo. Di 'Kamehameha' o 'Final Flash'!");
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
        case "d": this.combat.activateDodge(); break;
        case "r": 
          console.log("[Game] 'R' desactivado. Usa el gesto o la tecla 'K' para simular.");
          break;
        case "1": this.combat.triggerSpecial("kamehameha"); break;
        case "2": this.combat.triggerSpecial("finalFlash"); break;
        case "v": this.enterVR(); break;
        case "k": this.simulator.playRechargeSequence(); break;
        case "i": this.simulator.playKiBlastSequence("left"); break;
        case "o": this.simulator.playKiBlastSequence("right"); break;
      }
    });
  }

  /** Entrar en modo VR (llamable desde fuera, ej. botón VR del StartScreen) */
  async enterVR(): Promise<void> {
    if (this.xr) {
      await this.xr.baseExperience.enterXRAsync(
        'immersive-vr',
        'local-floor'
      );
    } else {
      // Si XR no está listo aún, esperar hasta 8s
      let waited = 0;
      const interval = setInterval(async () => {
        waited += 200;
        if (this.xr) {
          clearInterval(interval);
          await this.xr.baseExperience.enterXRAsync('immersive-vr', 'local-floor');
        } else if (waited >= 8000) {
          clearInterval(interval);
          console.warn('[XR] enterVR: timeout esperando xrHelper');
        }
      }, 200);
    }
  }

  private async initWebXR(): Promise<void> {
    // Verificar soporte WebXR antes de intentar inicializar
    if (!navigator.xr) {
      console.log("[XR] navigator.xr no disponible — modo desktop");
      return;
    }

    const supported = await navigator.xr.isSessionSupported("immersive-vr").catch(() => false);
    if (!supported) {
      console.log("[XR] immersive-vr no soportado en este dispositivo");
      return;
    }

    try {
      // Timeout de seguridad: si createDefaultXRExperienceAsync tarda más de 12s, abortar
      // dom-overlay: pasar el elemento directamente en la config (no con spread)
      // La propiedad no está en los tipos de Babylon pero sí es soportada en Quest
      const xrConfig: any = {
        uiOptions: {
          sessionMode: "immersive-vr",
          referenceSpaceType: "local-floor",
        },
        optionalFeatures: ["hand-tracking", "dom-overlay"],
        domOverlay: { element: this.xrOverlay },
      };
      const xrPromise = this.scene.createDefaultXRExperienceAsync(xrConfig);

      const timeoutPromise = new Promise<null>((_, reject) =>
        setTimeout(() => reject(new Error("XR init timeout")), 12000)
      );

      this.xr = await Promise.race([xrPromise, timeoutPromise]);

      if (!this.xr) {
        console.warn("[XR] xrHelper es null después de init");
        return;
      }

      // Deshabilitar puntero/laser de controladores (no se necesita con hand tracking)
      try {
        this.xr.baseExperience.featuresManager.disableFeature(WebXRFeatureName.POINTER_SELECTION);
        console.log("[XR] Puntero de controladores deshabilitado");
      } catch (e) {
        // El puntero puede no estar habilitado por defecto
      }

      // Deshabilitar teleportación (no queremos mover al jugador)
      try {
        this.xr.baseExperience.featuresManager.disableFeature(WebXRFeatureName.TELEPORTATION);
      } catch (e) {
        // Puede no estar habilitado
      }

      // Habilitar hand tracking con xrInput (requerido por Meta Quest)
      // Mostrar mallas 3D de manos en lugar de punteros
      let handTracking: any = null;
      try {
        handTracking = this.xr.baseExperience.featuresManager.enableFeature(
          WebXRFeatureName.HAND_TRACKING,
          "latest",
          {
            xrInput: this.xr.input,
            jointMeshes: {
              disableDefaultHandMesh: true,  // Forzar esferas primitivas en Meta Quest en vez de descargar 3D model
              enablePhysics: false
            },
          }
        );
        console.log("[XR] Hand tracking habilitado con manos 3D visibles");
      } catch (htErr) {
        console.warn("[XR] Hand tracking no disponible:", htErr);
      }

      // Ocultar manos estáticas cuando XR está activo
      // Adjuntar VRHud a la cámara XR al entrar en VR
      this.xr.baseExperience.onStateChangedObservable.add((state: number) => {
        // state 2 = IN_XR, state 0 = NOT_IN_XR
        const inXR = state === 2;

        if (inXR) {
          // Activar debug overlay
          this.debugOverlay?.show();

          // Adjuntar VRHud a la cámara XR
          const xrCamera = this.xr.baseExperience.camera;
          if (xrCamera) {
            // Instanciar el HUD 3D fijándolo en el espacio frente a la mirada del usuario
            if (this.vrHud) {
                // Retrasar la posición estática un frame para garantizar que el hardware Quest
                // entregó su vector rotacional real (y no spawnee en diagonal o neutro).
                this.xr.baseExperience.sessionManager.onXRFrameObservable.addOnce(() => {
                    this.vrHud.attachToXRCamera(xrCamera);
                    console.log("[XR] VRHud 3D anclado globalmente con el primer XRFrame válido.");
                });
            }
          }
          
          this.hud?.hide?.();
          this.debugOverlay?.hide(); // Forzar apagado de debug plano celeste antiguo
        } else {
          // Al salir de VR: ocultar UI 3D y mostrar UI 2D
          this.vrHud?.detachFromCamera();
          this.hud?.show?.();
          // El debugOverlay 2D puede persistir según el toggle
        }
        const leftMesh = this.scene.getMeshByName("leftHand");
        const rightMesh = this.scene.getMeshByName("rightHand");
        if (leftMesh)  leftMesh.isVisible  = !inXR;
        if (rightMesh) rightMesh.isVisible = !inXR;
        // También ocultar dedos
        for (let i = 0; i < 4; i++) {
          const lf = this.scene.getMeshByName(`lFinger${i}`);
          const rf = this.scene.getMeshByName(`rFinger${i}`);
          if (lf) lf.isVisible = !inXR;
          if (rf) rf.isVisible = !inXR;
        }
        ["lThumb", "rThumb"].forEach(n => {
          const m = this.scene.getMeshByName(n);
          if (m) m.isVisible = !inXR;
        });
      });

      // Loop de hand tracking usando la API correcta de Babylon 6:
      // WebXRHandTracking expone las manos a través de onHandAddedObservable
      // y las almacena en _handControllersCache (Map<XRHandedness, WebXRHand>)
      // Los joints se acceden via hand.getJointMesh(jointName).position
      let leftHand: any = null;
      let rightHand: any = null;

      if (handTracking) {
        // Suscribirse al observable de manos agregadas
        (handTracking as any).onHandAddedObservable?.add((hand: any) => {
          const handedness = hand.xrController?.inputSource?.handedness
            ?? hand.handedness
            ?? hand._handedness;
          console.log(`[XR] Mano detectada: ${handedness}`, Object.keys(hand));
          if (handedness === "left")  leftHand  = hand;
          if (handedness === "right") rightHand = hand;
        });
        (handTracking as any).onHandRemovedObservable?.add((hand: any) => {
          const handedness = hand.xrController?.inputSource?.handedness
            ?? hand.handedness
            ?? hand._handedness;
          if (handedness === "left")  leftHand  = null;
          if (handedness === "right") rightHand = null;
        });

        // Fallback: si el observable no dispara, intentar leer del cache cada 2s
        let fallbackTick = 0;
        this.scene.registerBeforeRender(() => {
          fallbackTick++;

          // Cada 120 frames (~2s) intentar leer del cache interno de Babylon
          if (fallbackTick % 60 === 0 && (!leftHand || !rightHand)) {
            const cache = (handTracking as any)._handControllersCache
              ?? (handTracking as any)._handControllers
              ?? (handTracking as any).handControllersCache;
            
            if (cache) {
              const handsArray = cache instanceof Map 
                ? Array.from(cache.values()) 
                : (Array.isArray(cache) ? cache : Object.values(cache));
                
              handsArray.forEach((h: any) => {
                 const hnd = h.xrController?.inputSource?.handedness ?? h.handedness ?? h._handedness;
                 if (hnd === "left") leftHand = h;
                 if (hnd === "right") rightHand = h;
              });
              
              if (leftHand || rightHand) {
                console.log(`[XR] Manos recobradas via cache (L:${!!leftHand} R:${!!rightHand})`);
              }
            }
          }

          // Extraer joints de las manos disponibles (solo de XR)
          let lJointsXR = leftHand  ? extractHandJoints(leftHand)  : null;
          let rJointsXR = rightHand ? extractHandJoints(rightHand) : null;

          // Si el simulador está inyectando posiciones, ignoramos el hardware basura / emulador
          if (this.simulator && this.simulator.isActive()) {
            lJointsXR = null;
            rJointsXR = null;
          }

          // Solo pasamos joints nativos de XR al recognizer
          if (lJointsXR) this.gestureRecognizer.updateHandJoints("left",  lJointsXR);
          if (rJointsXR) this.gestureRecognizer.updateHandJoints("right", rJointsXR);

          // IMPORTANTE: Obtenemos los joints ACTUALES desde el recognizer para el debug
          // (Así incluimos los datos del Simulator si están activos)
          const lJointsActual = this.gestureRecognizer.getLeftHandJoints();
          const rJointsActual = this.gestureRecognizer.getRightHandJoints();
          
          if (lJointsXR && rJointsXR) this.processGestures();

          // Construir apiSource para el debug overlay
          const apiSource = leftHand || rightHand
            ? `onHandAdded (L:${!!leftHand} R:${!!rightHand})`
            : `esperando manos...`;

          const currentGesture = this.gestureRecognizer.getCurrentGesture();

          this.debugOverlay?.update({
            handTrackingActive: this.handTrackingActive,
            leftJoints:  lJointsActual,
            rightJoints: rJointsActual,
            gesture: currentGesture,
            handApiSource: apiSource,
          });

          // Actualizar debug en VRHud también
          this.vrHud?.updateHandTrackingDebug(
            !!leftHand,
            !!rightHand,
            lJointsActual,
            rJointsActual,
            currentGesture,
            apiSource
          );
        });
      } else {
        // Sin hand tracking: actualizar overlay con estado vacío para mostrar el error
        this.scene.registerBeforeRender(() => {
          this.debugOverlay?.update({
            handTrackingActive: false,
            leftJoints:  null,
            rightJoints: null,
            gesture: this.gestureRecognizer.getCurrentGesture(),
            handApiSource: "handTracking feature = null",
          });
        });
      }

      console.log("[XR] WebXR inicializado correctamente");
    } catch (e) {
      console.warn("[XR] Error al inicializar WebXR:", e);
    }
  }

  private syncHandMeshes(): void {
    const lJoints = this.gestureRecognizer.getLeftHandJoints();
    const rJoints = this.gestureRecognizer.getRightHandJoints();

    // Actualizar estado de tracking activo (basado en si hay joints)
    const wasActive = this.handTrackingActive;
    this.handTrackingActive = !!(lJoints || rJoints);

    if (this.handTrackingActive) {
      // Detener animaciones automáticas si hay control manual/simulado
      if (!wasActive && this.leftPalmMesh) {
         this.scene.stopAnimation(this.leftPalmMesh);
         this.scene.stopAnimation(this.rightPalmMesh);
         console.log("[Game] Animación de manos detenida para modo Tracking/Simulación");
      }

      if (this.leftPalmMesh && lJoints) {
        this.leftPalmMesh.position.copyFromFloats(lJoints.wrist.x, lJoints.wrist.y, lJoints.wrist.z);
      }
      if (this.rightPalmMesh && rJoints) {
        this.rightPalmMesh.position.copyFromFloats(rJoints.wrist.x, rJoints.wrist.y, rJoints.wrist.z);
      }
    }

    // ACTUALIZACIÓN DE AURAS
    const stats = this.combat.getStats();
    const activeCombo = this.gestureRecognizer.getActiveCombo();
    
    // El jugador carga si está en RECHARGING o en fase de CHARGED_KI_BLAST
    const isPlayerCharging = stats.combatState === "slowMotion" || 
                           activeCombo === "CHARGED_KI_BLAST_L" || 
                           activeCombo === "CHARGED_KI_BLAST_R" ||
                           this.gestureRecognizer.getCurrentGesture() === "RECHARGING";

    if (this.playerAura) {
      // El aura sigue a la cámara (pero quizás un poco abajo)
      this.playerAura.emitter = new Vector3(this.camera.position.x, this.camera.position.y - 0.5, this.camera.position.z);
      const colorHex = gokuConfig.transformations?.[0]?.props?.color_palette || "#3b82f6";
      const pColor = Color4.FromHexString(colorHex.length === 7 ? colorHex + "cc" : colorHex);
      this.vfx.updateAura(this.playerAura, (stats.playerKi / 100) * 100, isPlayerCharging, stats.playerNP, pColor);
    }

    if (this.enemyAura) {
      const colorHex = vegetaConfig.transformations?.[0]?.props?.color_palette || "#1e1b4b";
      const eColor = Color4.FromHexString(colorHex.length === 7 ? colorHex + "cc" : colorHex);
      this.vfx.updateAura(this.enemyAura, (stats.enemyKi / 100) * 100, stats.combatState === "slowMotion", stats.enemyNP, eColor);
    }

    // Si estamos en modo simulación (sin XR activo), procesamos los gestos aquí
    const inXR = this.xr?.baseExperience?.state === 2; // 2 = IN_XR
    if (!inXR && this.handTrackingActive) {
      this.processGestures();
    }
  }

  private processGestures(): void {
    const gesture = this.gestureRecognizer.getCurrentGesture();
    const gestureChanged = gesture !== this.lastReportedGesture;
    const activeCombo = this.gestureRecognizer.getActiveCombo();
    const comboStep = this.gestureRecognizer.getComboStep();
    const now = Date.now();

    // LÓGICA DE CARGA EN PASO INTERMEDIO (PARA CHARGED BLAST)
    if (now - this.lastChargeUpdateTime > 100) {
      this.lastChargeUpdateTime = now;
      
      const stats = this.combat.getStats();

      if (activeCombo === "CHARGED_KI_BLAST_L" && comboStep === 1) {
           if (this.leftChargeStartKi === 0) this.leftChargeStartKi = stats.playerKi;
           // Limitar el gasto al 20% del KI inicial
           const canSpend = (stats.playerKi > this.leftChargeStartKi * 0.8);

           if (canSpend && this.leftChargePower < 3.5 && this.combat.consumeKi(4)) {
              this.leftChargePower += 0.2;
              this.vrHud?.showToast(`CARGANDO L: x${this.leftChargePower.toFixed(1)}`, "#ff8800", 0);
           }
      } else if (activeCombo === "CHARGED_KI_BLAST_R" && comboStep === 1) {
           if (this.rightChargeStartKi === 0) this.rightChargeStartKi = stats.playerKi;
           const canSpend = (stats.playerKi > this.rightChargeStartKi * 0.8);

           if (canSpend && this.rightChargePower < 3.5 && this.combat.consumeKi(4)) {
              this.rightChargePower += 0.2;
              this.vrHud?.showToast(`CARGANDO R: x${this.rightChargePower.toFixed(1)}`, "#ff8800", 0);
           }
      } else {
          // Resetear potencia y KI de inicio si NO estamos cargando Y NO acabamos de completar el gesto
          if (gesture !== "CHARGED_KI_BLAST_L") {
            this.leftChargePower = 1.0;
            this.leftChargeStartKi = 0;
          }
          if (gesture !== "CHARGED_KI_BLAST_R") {
            this.rightChargePower = 1.0;
            this.rightChargeStartKi = 0;
          }
      }
    }
    
    // Detectar cancelaciones (pasar de PREP a IDLE sin llegar a RECHARGING)
    if (gestureChanged && this.lastReportedGesture === "RECHARGE_PREP" && gesture === "IDLE") {
      this.vrHud?.showToast("Secuencia Cancelada", "#ff4444", 2000);
    }
    
    // Si estábamos recargando y la postura cambió, DETENEMOS la recarga
    if (gestureChanged && this.lastReportedGesture === "RECHARGING") {
      this.combat.stopRecharge();
      this.vrHud?.showToast("Fin de Recarga", "#aaaaaa", 1500);
    }
    
    this.lastReportedGesture = gesture;
    let success = false;

    switch (gesture) {
      case "ATTACKING":
        success = this.combat.launchBasicAttack();
        if (gestureChanged) {
          this.vrHud?.showToast(success ? "¡ATAQUE BÁSICO!" : "Sin KI", success ? "#ff4444" : "#aaaaaa");
        }
        break;
      case "CHARGING":
        success = this.combat.startChargedAttack();
        if (gestureChanged) this.vrHud?.showToast("Cargando...", "#ffcc00");
        break;
      case "BLOCKING":
        success = this.combat.activateBlock();
        if (gestureChanged && success) this.vrHud?.showToast("¡BLOQUEO!", "#44ff44");
        break;
      case "RECHARGING":
        success = this.combat.rechargeKi();
        if (gestureChanged) {
           this.vrHud?.showToast("¡RECARGANDO KI!", "#cc44ff", 0);
        }
        break;
      case "RECHARGE_PREP":
        success = false; // Falso para no saturar el log visual de debug, pero el gesto es válido
        if (gestureChanged) {
           this.vrHud?.showToast("Fase 1: Preparando...", "#ff8800", 0);
        }
        break;
      case "KAMEHAMEHA_PREP":
        success = false;
        if (gestureChanged) {
           this.vrHud?.showToast("KA... ME...", "#00e5ff", 0);
        }
        break;
      case "KAMEHAMEHA":
        success = true; // TODO: Lógica de combate de Kamehameha real
        if (gestureChanged) {
           this.vrHud?.showToast("¡HAAAAAAAAAA!", "#00e5ff", 4000);
           // Efecto de impacto global
           this.vfx.spawnImpact({x: 0, y: 1.5, z: 2}, "heavy");
        }
        break;
      case "KI_BLAST_L": {
        const now = performance.now();
        // Evitar disparo normal si acabamos de hacer uno cargado (grace period 500ms)
        if (now - this.lastChargedFireTime < 500) break;
        if (now - this.lastKiBlastTime < 400) break;
        this.lastKiBlastTime = now;
        
        const L = this.gestureRecognizer.getLeftHandJoints();
        if (L) {
          const forward = this.camera.getForwardRay().direction;
          // Si hay carga acumulada, la usamos (pero en teoría este caso es para el blast normal)
          success = this.combat.launchKiBlast(L.wrist, forward, 1.0);
          this.vrHud?.showToast(success ? "KI BLAST L" : "Sin Ki", success ? "#eeff00" : "#aaaaaa", 1000);
        }
        break;
      }
      case "KI_BLAST_R": {
        const now = performance.now();
        if (now - this.lastChargedFireTime < 500) break;
        if (now - this.lastKiBlastTime < 400) break;
        this.lastKiBlastTime = now;
        
        const R = this.gestureRecognizer.getRightHandJoints();
        if (R) {
          const forward = this.camera.getForwardRay().direction;
          success = this.combat.launchKiBlast(R.wrist, forward, 1.0);
          this.vrHud?.showToast(success ? "KI BLAST R" : "Sin Ki", success ? "#eeff00" : "#aaaaaa", 1000);
        }
        break;
      }
      case "CHARGED_KI_BLAST_L": {
        const L = this.gestureRecognizer.getLeftHandJoints();
        if (L) {
           const forward = this.camera.getForwardRay().direction;
           success = this.combat.launchKiBlast(L.wrist, forward, this.leftChargePower);
           this.vrHud?.showToast(`¡CARGA: x${this.leftChargePower.toFixed(1)}!`, "#ff00ff", 1500);
           this.leftChargePower = 1.0; 
           this.lastChargedFireTime = performance.now();
        }
        break;
      }
      case "CHARGED_KI_BLAST_R": {
        const R = this.gestureRecognizer.getRightHandJoints();
        if (R) {
           const forward = this.camera.getForwardRay().direction;
           success = this.combat.launchKiBlast(R.wrist, forward, this.rightChargePower);
           this.vrHud?.showToast(`¡CARGA: x${this.rightChargePower.toFixed(1)}!`, "#ff00ff", 1500);
           this.rightChargePower = 1.0;
           this.lastChargedFireTime = performance.now();
        }
        break;
      }
      case "IDLE":
        success = true;
        if (gestureChanged) {
            const wasAction = this.lastReportedGesture.startsWith("KI_BLAST") || this.lastReportedGesture === "KAMEHAMEHA";
            // Si venimos de un ataque exitoso, dejamos que su propio timer lo oculte. 
            // Si es un cambio manual a reposo, ocultamos al instante.
            if (!wasAction) {
                this.vrHud?.hideToast();
            }
        }
        break;
    }

    // Actualizar debug de overlay (Desktop)
    this.debugOverlay?.update({
      handTrackingActive: true,
      leftJoints:  this.gestureRecognizer.getLeftHandJoints(),
      rightJoints: this.gestureRecognizer.getRightHandJoints(),
      gesture: gesture,
      success: success
    });

    // Actualizar debug en VRHud (VR)
    if (this.vrHud?.isVisible()) {
      this.vrHud.updateHandTrackingDebug(
        true, true,
        this.gestureRecognizer.getLeftHandJoints(),
        this.gestureRecognizer.getRightHandJoints(),
        gesture,
        "WebXR + Success Check"
      );
    }
  }

  /** Salir de la sesión XR si está activa y luego limpiar el motor */
  async disposeAndExit(): Promise<void> {
    try {
      if (this.xr?.baseExperience) {
        const state = this.xr.baseExperience.state;
        // state 2 = IN_XR
        if (state === 2) {
          await this.xr.baseExperience.exitXRAsync();
        }
      }
    } catch (_) { /* ignorar si ya no está en XR */ }
    this.voiceRecognizer?.stop();
    this.engine.dispose();
  }

  dispose(): void {
    this.engine.dispose();
  }
}
