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
  WebXRFeatureName,
} from "@babylonjs/core";
import { HUD } from "./HUD";
import { CombatSystem } from "./CombatSystem";
import { VFXManager } from "./VFXManager";
import { GestureRecognizer, extractHandJoints } from "./GestureRecognizer";
import { GestureDebugOverlay } from "./GestureDebugOverlay";
import { VoiceRecognizer } from "./VoiceRecognizer";
import { ResultScreen } from "./ResultScreen";
import { VRHud } from "./VRHud";

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
  private xr: any = null;
  private started = false;
  private menuCallback: (() => void) | null = null;
  private debugOverlay!: GestureDebugOverlay;
  private handTrackingActive = false;
  private vrHud!: VRHud;

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
    this.setupEnvironment();

    this.vfx = new VFXManager(this.scene);
    this.combat = new CombatSystem(this.scene, this.vfx);
    this.gestureRecognizer = new GestureRecognizer(this.scene);
    // VRHud: HUD 3D world-space para Meta Quest 3
    // Se crea aquí pero se adjunta a la cámara XR en initWebXR()
    this.vrHud = new VRHud(this.scene, this.combat);
    // Montar HUD, ResultScreen y DebugOverlay en el xrOverlay
    // para que sean visibles dentro del visor XR via dom-overlay
    this.hud = new HUD(this.xrOverlay, this.combat);
    this.voiceRecognizer = new VoiceRecognizer();
    this.resultScreen = new ResultScreen(this.xrOverlay);
    this.debugOverlay = new GestureDebugOverlay(this.xrOverlay);

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
    const leftPalm = MeshBuilder.CreateBox("leftHand", { width: 0.22, height: 0.06, depth: 0.28 }, this.scene);
    leftPalm.position = new Vector3(-0.52, 1.12, 0.55);
    leftPalm.rotation = new Vector3(-0.35, 0.12, 0.18);
    leftPalm.material = handMat;

    // Dedos izquierda (4 cajas)
    for (let i = 0; i < 4; i++) {
      const finger = MeshBuilder.CreateBox(`lFinger${i}`, { width: 0.04, height: 0.04, depth: 0.14 }, this.scene);
      finger.position = new Vector3(
        leftPalm.position.x - 0.07 + i * 0.05,
        leftPalm.position.y - 0.01,
        leftPalm.position.z + 0.19
      );
      finger.rotation = leftPalm.rotation.clone();
      finger.material = handMat;
    }
    // Pulgar izquierdo
    const lThumb = MeshBuilder.CreateBox("lThumb", { width: 0.05, height: 0.04, depth: 0.10 }, this.scene);
    lThumb.position = new Vector3(leftPalm.position.x + 0.14, leftPalm.position.y, leftPalm.position.z + 0.06);
    lThumb.rotation = new Vector3(-0.2, 0.5, 0.3);
    lThumb.material = handMat;

    // Mano derecha — palma + dedos
    const rightPalm = MeshBuilder.CreateBox("rightHand", { width: 0.22, height: 0.06, depth: 0.28 }, this.scene);
    rightPalm.position = new Vector3(0.52, 1.12, 0.55);
    rightPalm.rotation = new Vector3(-0.35, -0.12, -0.18);
    rightPalm.material = handMat;

    for (let i = 0; i < 4; i++) {
      const finger = MeshBuilder.CreateBox(`rFinger${i}`, { width: 0.04, height: 0.04, depth: 0.14 }, this.scene);
      finger.position = new Vector3(
        rightPalm.position.x + 0.07 - i * 0.05,
        rightPalm.position.y - 0.01,
        rightPalm.position.z + 0.19
      );
      finger.rotation = rightPalm.rotation.clone();
      finger.material = handMat;
    }
    const rThumb = MeshBuilder.CreateBox("rThumb", { width: 0.05, height: 0.04, depth: 0.10 }, this.scene);
    rThumb.position = new Vector3(rightPalm.position.x - 0.14, rightPalm.position.y, rightPalm.position.z + 0.06);
    rThumb.rotation = new Vector3(-0.2, -0.5, -0.3);
    rThumb.material = handMat;

    // Aura de KI azul alrededor de las manos
    const kiAura = new ParticleSystem("handAura", 120, this.scene);
    kiAura.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    kiAura.emitter = leftPalm;
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
    leftPalm.animations  = [breathAnim];
    rightPalm.animations = [breathAnim];
    this.scene.beginAnimation(leftPalm,  0, 100, true);
    this.scene.beginAnimation(rightPalm, 0, 100, true);
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
      if (!this.started) return;
      console.log(`[Voice] Comando detectado: ${command} ("${transcript}")`);
      if (command === "kamehameha") {
        this.combat.kamehamehaStep(1);
        // Bonus de NP por gritar el ataque
        this.combat.applyVoiceBonus("kamehameha");
      } else if (command === "finalFlash") {
        this.combat.finalFlashStep(1);
        this.combat.applyVoiceBonus("finalFlash");
      }
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
        case "r": this.combat.rechargeKi(); break;
        case "1": this.combat.kamehamehaStep(1); break;
        case "2": this.combat.finalFlashStep(1); break;
        case "v": this.enterVR(); break;
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

      // Habilitar hand tracking con xrInput (requerido por Meta Quest)
      let handTracking: any = null;
      try {
        handTracking = this.xr.baseExperience.featuresManager.enableFeature(
          WebXRFeatureName.HAND_TRACKING,
          "latest",
          {
            xrInput: this.xr.input,
            jointMeshes: {
              disableDefaultHandMesh: true,
              invisible: true,
            },
          }
        );
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

          // Adjuntar VRHud a la cámara XR y ocultar HUD HTML
          // La cámara XR está disponible justo después de que la sesión inicia
          const xrCamera = this.xr.baseExperience.camera;
          if (xrCamera && this.vrHud) {
            this.vrHud.attachToXRCamera(xrCamera);
            console.log("[VRHud] Adjuntado a cámara XR");
          }
          // Ocultar el HUD HTML (no visible en immersive-vr de todos modos)
          this.hud?.hide?.();
        } else {
          // Al salir de VR: mostrar HUD HTML, ocultar VRHud
          this.vrHud?.detachFromCamera();
          this.hud?.show?.();
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
          if (fallbackTick % 120 === 0 && (!leftHand || !rightHand)) {
            const cache = (handTracking as any)._handControllersCache
              ?? (handTracking as any)._handControllers
              ?? (handTracking as any).handControllersCache;
            if (cache instanceof Map) {
              leftHand  = cache.get("left")  ?? leftHand;
              rightHand = cache.get("right") ?? rightHand;
              if (leftHand || rightHand) {
                console.log("[XR] Manos encontradas via cache:", !!leftHand, !!rightHand);
              }
            }
          }

          // Extraer joints de las manos disponibles
          const lJoints = leftHand  ? extractHandJoints(leftHand)  : null;
          const rJoints = rightHand ? extractHandJoints(rightHand) : null;

          this.handTrackingActive = !!(lJoints || rJoints);

          if (lJoints) this.gestureRecognizer.updateHandJoints("left",  lJoints);
          if (rJoints) this.gestureRecognizer.updateHandJoints("right", rJoints);
          if (lJoints && rJoints) this.processGestures();

          // Construir apiSource para el debug overlay
          const apiSource = leftHand || rightHand
            ? `onHandAdded (L:${!!leftHand} R:${!!rightHand})`
            : `esperando manos...`;

          this.debugOverlay?.update({
            handTrackingActive: this.handTrackingActive,
            leftJoints:  lJoints,
            rightJoints: rJoints,
            gesture: this.gestureRecognizer.getCurrentGesture(),
            handApiSource: apiSource,
          });
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

  private processGestures(): void {
    const gesture = this.gestureRecognizer.getCurrentGesture();
    switch (gesture) {
      case "ATTACKING":
        if (!this.combat.isInChargingState()) this.combat.launchBasicAttack();
        break;
      case "CHARGING":
        this.combat.startChargedAttack();
        break;
      case "BLOCKING":
        this.combat.activateBlock();
        break;
      case "RECHARGING":
        this.combat.rechargeKi();
        break;
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
