// Tree-shakeable imports de Babylon.js
import { Engine } from "@babylonjs/core/Engines/engine.js";
import { Scene } from "@babylonjs/core/scene.js";
import { ArcRotateCamera } from "@babylonjs/core/Cameras/arcRotateCamera.js";
import { Vector3 } from "@babylonjs/core/Maths/math.vector.js";
import { Color3 } from "@babylonjs/core/Maths/math.color.js";
import { Color4 } from "@babylonjs/core/Maths/math.color.js";
import { MeshBuilder } from "@babylonjs/core/Meshes/meshBuilder.js";
import { StandardMaterial } from "@babylonjs/core/Materials/standardMaterial.js";
import { Texture } from "@babylonjs/core/Materials/Textures/texture.js";
import { Mesh } from "@babylonjs/core/Meshes/mesh.js";
import { HemisphericLight } from "@babylonjs/core/Lights/hemisphericLight.js";
import { PointLight } from "@babylonjs/core/Lights/pointLight.js";
import { ParticleSystem } from "@babylonjs/core/Particles/particleSystem.js";

// WebXR imports
import { WebXRDefaultExperience } from "@babylonjs/core/XR/webXRDefaultExperience.js";
import { WebXRFeatureName } from "@babylonjs/core/XR/webXRFeaturesManager.js";
import { WebXRHandTracking } from "@babylonjs/core/XR/features/WebXRHandTracking.js";
import { WebXRHandJoint } from "@babylonjs/core/XR/features/WebXRHandTracking.js";
import "@babylonjs/core/Materials/Textures/Loaders";
import "@babylonjs/loaders/glTF";

// ============================================
// CONFIGURACIÓN DEL JUEGO
// ============================================
const CONFIG = {
  playerSpeed: 0.5,
  boostMultiplier: 2.5,
  kamehamehaSpeed: 2,
  cameraHeight: 1.7, // Altura ojos
};

// ============================================
// CLASE PRINCIPAL
// ============================================
class DragonBallVR {
  private engine: Engine;
  private scene: Scene;
  private camera!: ArcRotateCamera;
  private player!: Mesh;
  private xrHelper: any;
  private kamehamehaReady = true;
  private keys: { [key: string]: boolean } = {};

  constructor() {
    // Crear engine
    const canvas = document.getElementById("renderCanvas") as HTMLCanvasElement;
    this.engine = new Engine(canvas, true, { 
      preserveDrawingBuffer: true, 
      stencil: true,
      antialias: true
    });

    // Crear escena
    this.scene = new Scene(this.engine);
    this.scene.clearColor = new Color4(0.05, 0.05, 0.1, 1);
    this.scene.ambientColor = new Color3(0.3, 0.3, 0.3);
    this.scene.gravity = new Vector3(0, -0.9, 0);
    this.scene.collisionsEnabled = true;

    this.setupCamera();
    this.setupLighting();
    this.setupEnvironment();
    this.setupPlayer();
    this.setupControls();
    this.setupWebXR();
    this.setupVRButton();

    // Loop de render
    this.engine.runRenderLoop(() => {
      this.update();
      this.scene.render();
    });

    // Resize
    window.addEventListener("resize", () => {
      this.engine.resize();
    });
  }

  // ============================================
  // CÁMARA
  // ============================================
  private setupCamera() {
    this.camera = new ArcRotateCamera(
      "camera",
      Math.PI / 2,
      Math.PI / 2.5,
      10,
      new Vector3(0, CONFIG.cameraHeight, 0),
      this.scene
    );
    this.camera.attachControl(document.getElementById("renderCanvas"), true);
    this.camera.speed = 0.5;
    this.camera.angularSensibility = 2000;
    this.camera.collisionRadius = new Vector3(0.5, 0.5, 0.5);
    this.camera.checkCollisions = true;
    
    // Limitar ángulos
    this.camera.lowerBetaLimit = 0.1;
    this.camera.upperBetaLimit = Math.PI - 0.1;
  }

  // ============================================
  // ILUMINACIÓN
  // ============================================
  private setupLighting() {
    // Luz ambiental
    const ambient = new HemisphericLight(
      "ambient",
      new Vector3(0, 1, 0),
      this.scene
    );
    ambient.intensity = 0.6;
    ambient.groundColor = new Color3(0.2, 0.2, 0.3);

    // Sol (estilo Dragon Ball - anaranjado/amarillo)
    const sun = new PointLight(
      "sun",
      new Vector3(50, 100, 50),
      this.scene
    );
    sun.intensity = 1.2;
    sun.diffuse = new Color3(1, 0.9, 0.7);
    sun.specular = new Color3(1, 0.8, 0.5);
  }

  // ============================================
  // ENTORNO
  // ============================================
  private setupEnvironment() {
    // Skybox estilo espacio/otro mundo
    const skybox = MeshBuilder.CreateBox("skyBox", { size: 1000 }, this.scene);
    const skyboxMaterial = new StandardMaterial("skyBoxMat", this.scene);
    skyboxMaterial.backFaceCulling = false;
    skyboxMaterial.disableLighting = true;
    skyboxMaterial.diffuseColor = new Color3(0, 0, 0);
    skyboxMaterial.specularColor = new Color3(0, 0, 0);
    skyboxMaterial.emissiveColor = new Color3(0.02, 0.02, 0.08);
    skybox.material = skyboxMaterial;
    skybox.infiniteDistance = true;

    // Planeta suelo - estilo Namek
    const ground = MeshBuilder.CreateGround(
      "ground",
      { width: 500, height: 500, subdivisions: 50 },
      this.scene
    );
    const groundMat = new StandardMaterial("groundMat", this.scene);
    groundMat.diffuseColor = new Color3(0.2, 0.5, 0.2);
    groundMat.specularColor = new Color3(0.1, 0.1, 0.1);
    ground.material = groundMat;
    ground.checkCollisions = true;

    // Montañas/rocas
    for (let i = 0; i < 30; i++) {
      const rock = MeshBuilder.CreatePolyhedron(
        `rock${i}`,
        { type: Math.floor(Math.random() * 3), size: Math.random() * 5 + 2 },
        this.scene
      );
      rock.position = new Vector3(
        (Math.random() - 0.5) * 200,
        Math.random() * 3,
        (Math.random() - 0.5) * 200
      );
      rock.rotation = new Vector3(
        Math.random() * Math.PI,
        Math.random() * Math.PI,
        Math.random() * Math.PI
      );
      const rockMat = new StandardMaterial(`rockMat${i}`, this.scene);
      rockMat.diffuseColor = new Color3(0.4, 0.35, 0.3);
      rock.material = rockMat;
      rock.checkCollisions = true;
    }

    // Torres de entrenamiento estilo Tierra
    for (let i = 0; i < 5; i++) {
      const tower = MeshBuilder.CreateCylinder(
        `tower${i}`,
        { height: 30 + Math.random() * 20, diameter: 8, tessellation: 8 },
        this.scene
      );
      tower.position = new Vector3(
        (Math.random() - 0.5) * 150,
        15,
        (Math.random() - 0.5) * 150
      );
      const towerMat = new StandardMaterial(`towerMat${i}`, this.scene);
      towerMat.diffuseColor = new Color3(0.8, 0.8, 0.85);
      tower.material = towerMat;
      tower.checkCollisions = true;
    }
  }

  // ============================================
  // JUGADOR
  // ============================================
  private setupPlayer() {
    // Esfera representando al jugador
    this.player = MeshBuilder.CreateSphere(
      "player",
      { diameter: 1, segments: 16 },
      this.scene
    );
    this.player.position = new Vector3(0, CONFIG.cameraHeight, 0);
    this.player.visibility = 0.3;
    this.player.isPickable = false;

    // Collision ellipsoid
    this.player.ellipsoid = new Vector3(0.5, 0.9, 0.5);
    this.player.checkCollisions = true;

    // Material energy
    const playerMat = new StandardMaterial("playerMat", this.scene);
    playerMat.diffuseColor = new Color3(1, 0.6, 0);
    playerMat.emissiveColor = new Color3(0.3, 0.1, 0);
    playerMat.alpha = 0.5;
    this.player.material = playerMat;
  }

  // ============================================
  // CONTROLES ESCRITORIO
  // ============================================
  private setupControls() {
    // Keyboard
    window.addEventListener("keydown", (e) => {
      this.keys[e.key.toLowerCase()] = true;
      
      // Kamehameha
      if (e.key === " " || e.key.toLowerCase() === "k") {
        this.fireKamehameha();
      }
      
      // Puño
      if (e.key.toLowerCase() === "e") {
        this.throwPunch();
      }
    });

    window.addEventListener("keyup", (e) => {
      this.keys[e.key.toLowerCase()] = false;
    });

    // Mouse click para Kamehameha
    const canvas = document.getElementById("renderCanvas");
    canvas?.addEventListener("click", () => {
      this.fireKamehameha();
    });
  }

  // ============================================
  // WEBXR (META QUEST) - API NUEVA
  // ============================================
  private async setupWebXR() {
    try {
      // Usar la nueva API WebXRDefaultExperience.CreateAsync
      const ground = this.scene.getMeshByName("ground") as Mesh;
      
      this.xrHelper = await WebXRDefaultExperience.CreateAsync(this.scene, {
        floorMeshes: [ground],
        disableTeleportation: false,
        optionalFeatures: true
      });

      // Habilitar HAND TRACKING
      const handTracking = this.xrHelper.featuresManager.enableFeature(
        WebXRFeatureName.HAND_TRACKING,
        "stable",
        {
          xrInput: this.xrHelper.input,
          jointMeshes: {
            enablePhysics: false,
            disableDefaultHandMesh: false,
            returnDefaultTargetMeshIfNotFound: true
          }
        }
      ) as WebXRHandTracking;

      // Hand tracking events - Pinch para Kamehameha
      handTracking.onHandAddedObservable.add((hand: any) => {
        console.log("🖐️ Mano detectada:", hand.handness);
        
        const indexTip = hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP);
        const thumbTip = hand.getJointMesh(WebXRHandJoint.THUMB_TIP);
        let grabbed = false;

        this.scene.onBeforeRenderObservable.add(() => {
          if (indexTip && thumbTip) {
            const dist = Vector3.Distance(indexTip.position, thumbTip.position);
            
            // Pinch detectado (dedo índice + pulgar juntos)
            if (!grabbed && dist < 0.03) {
              grabbed = true;
              this.fireKamehameha();
            }
            if (grabbed && dist > 0.05) {
              grabbed = false;
            }
          }
        });
      });

      // Configurar movimiento con controllers
      if (this.xrHelper.movement) {
        this.xrHelper.movement.movePlayerOnNavigationStart = true;
      }

      // Input: trigger para Kamehameha (controllers)
      this.xrHelper.input.onControllerAddedObservable.add((controller: any) => {
        controller.onMotionControllerInitObservable.add((motionController: any) => {
          // Trigger
          const trigger = motionController.getComponent("xr-standard-trigger");
          if (trigger) {
            trigger.onButtonStateChangedObservable.add(() => {
              if (trigger.pressed) {
                this.fireKamehameha();
              }
            });
          }
          
          // Squeeze para puño
          const squeeze = motionController.getComponent("xr-standard-squeeze");
          if (squeeze) {
            squeeze.onButtonStateChangedObservable.add(() => {
              if (squeeze.pressed) {
                this.throwPunch();
              }
            });
          }
        });
      });

      console.log("✅ WebXR configurado con Hand Tracking para Meta Quest");
    } catch (err) {
      console.log("⚠️ WebXR no disponible:", err);
    }
  }

  // ============================================
  // BOTÓN VR
  // ============================================
  private setupVRButton() {
    const vrButton = document.getElementById("vrButton");
    if (!vrButton) return;

    this.scene.onReadyObservable.add(() => {
      if (this.xrHelper?.baseExperience) {
        this.xrHelper.baseExperience.stateChangedObservable.add((state: any) => {
          if (state === 0) { // NOT_IN_XR
            vrButton.style.display = "block";
          } else {
            vrButton.style.display = "none";
          }
        });
      }
    });

    vrButton.addEventListener("click", async () => {
      if (this.xrHelper?.baseExperience) {
        try {
          await this.xrHelper.baseExperience.enterXRAsync(
            "immersive-vr",
            "local-floor"
          );
        } catch (err) {
          console.error("Error entrando en VR:", err);
          alert("No se pudo entrar en VR. ¿Tienes el casco conectado?");
        }
      }
    });
  }

  // ============================================
  // UPDATE LOOP
  // ============================================
  private update() {
    const deltaTime = this.engine.getDeltaTime() / 1000;
    this.updateMovement(deltaTime);
    this.updateCamera();
  }

  private updateMovement(dt: number) {
    if (!this.player) return;

    const speed = this.keys["shift"] 
      ? CONFIG.playerSpeed * CONFIG.boostMultiplier 
      : CONFIG.playerSpeed;

    let moveDirection = new Vector3(0, 0, 0);

    // WASD
    if (this.keys["w"]) moveDirection.z += 1;
    if (this.keys["s"]) moveDirection.z -= 1;
    if (this.keys["a"]) moveDirection.x -= 1;
    if (this.keys["d"]) moveDirection.x += 1;

    // Q/E arriba/abajo
    if (this.keys["q"]) moveDirection.y -= 1;
    if (this.keys["e"]) moveDirection.y += 1;

    if (moveDirection.length() > 0) {
      moveDirection.normalize();
      
      // Rotar según la cámara
      const cameraDirection = this.camera.getDirection(Vector3.Forward());
      cameraDirection.y = 0;
      cameraDirection.normalize();
      
      const cameraRight = this.camera.getDirection(Vector3.Right());
      cameraRight.y = 0;
      cameraRight.normalize();

      const finalMove = 
        cameraDirection.scale(moveDirection.z)
        .add(cameraRight.scale(moveDirection.x))
        .add(new Vector3(0, moveDirection.y, 0));

      this.player.position.addInPlace(finalMove.scale(speed));
      this.camera.target = this.player.position.clone();
    }
  }

  private updateCamera() {
    if (this.player && !this.xrHelper?.baseExperience?.state) {
      // Seguir al jugador suavemente
      this.camera.target = Vector3.Lerp(
        this.camera.target,
        this.player.position,
        0.1
      );
    }
  }

  // ============================================
  // KAMEHAMEHA
  // ============================================
  private fireKamehameha() {
    if (!this.kamehamehaReady || !this.player) return;

    this.kamehamehaReady = false;

    // Crear beam de energía
    const beam = MeshBuilder.CreateCylinder(
      "kamehameha",
      { height: 5, diameter: 0.5, tessellation: 16 },
      this.scene
    );
    
    // Posicionar frente al jugador
    const forward = this.camera.getDirection(Vector3.Forward());
    beam.position = this.player.position.add(forward.scale(3));
    beam.lookAt(beam.position.add(forward));
    beam.rotation.x += Math.PI / 2;

    // Material energy azul/amarillo
    const beamMat = new StandardMaterial("beamMat", this.scene);
    beamMat.diffuseColor = new Color3(0.3, 0.5, 1);
    beamMat.emissiveColor = new Color3(0.2, 0.4, 1);
    beamMat.alpha = 0.8;
    beam.material = beamMat;

    // Partículas
    const particles = new ParticleSystem("particles", 2000, this.scene);
    particles.particleTexture = new Texture(
      "https://assets.babylonjs.com/textures/flare.png",
      this.scene
    );
    particles.emitter = beam.position.clone();
    particles.minSize = 0.1;
    particles.maxSize = 0.3;
    particles.minLifeTime = 0.2;
    particles.maxLifeTime = 0.5;
    particles.emitRate = 500;
    particles.direction1 = forward.scale(-10);
    particles.direction2 = forward.scale(-15);
    particles.color1 = new Color4(0.3, 0.5, 1, 1);
    particles.color2 = new Color4(1, 1, 0.5, 1);
    particles.colorDead = new Color4(0, 0, 0.5, 0);
    particles.minEmitPower = 5;
    particles.maxEmitPower = 10;
    particles.start();

    // Animar beam
    let beamLife = 0;
    const beamObserver = this.scene.onBeforeRenderObservable.add(() => {
      beamLife += this.engine.getDeltaTime() / 1000;
      beam.position.addInPlace(forward.scale(CONFIG.kamehamehaSpeed));
      particles.emitter = beam.position.clone();

      if (beamLife > 2) {
        particles.stop();
        beam.dispose();
        this.scene.onBeforeRenderObservable.remove(beamObserver);
        setTimeout(() => {
          this.kamehamehaReady = true;
        }, 1000);
      }
    });
  }

  // ============================================
  // PUÑO
  // ============================================
  private throwPunch() {
    if (!this.player) return;

    // Crear efecto de puño
    const fist = MeshBuilder.CreateSphere(
      "fist",
      { diameter: 0.5 },
      this.scene
    );

    const forward = this.camera.getDirection(Vector3.Forward());
    fist.position = this.player.position.add(forward.scale(1.5));

    const fistMat = new StandardMaterial("fistMat", this.scene);
    fistMat.diffuseColor = new Color3(1, 0.5, 0);
    fistMat.emissiveColor = new Color3(0.5, 0.2, 0);
    fist.material = fistMat;

    // Animar puño
    let fistLife = 0;
    const fistObserver = this.scene.onBeforeRenderObservable.add(() => {
      fistLife += this.engine.getDeltaTime() / 1000;
      fist.position.addInPlace(forward.scale(0.3));

      if (fistLife > 0.5) {
        fist.dispose();
        this.scene.onBeforeRenderObservable.remove(fistObserver);
      }
    });
  }
}

// ============================================
// INICIAR JUEGO
// ============================================
window.addEventListener("DOMContentLoaded", () => {
  new DragonBallVR();
});