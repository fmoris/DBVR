import {
  Scene,
  Vector3,
  HemisphericLight,
  DirectionalLight,
  Color3,
  Color4,
  MeshBuilder,
  StandardMaterial,
  Mesh,
  SceneLoader,
  AbstractMesh,
  Skeleton,
  Quaternion,
  BoneIKController,
  TransformNode
} from "@babylonjs/core";
import "@babylonjs/loaders/glTF";

export class EnvironmentManager {
  private leftPalmMesh?: Mesh;
  private rightPalmMesh?: Mesh;
  private enemyRoot?: AbstractMesh;
  private enemySkeleton?: Skeleton;
  private enemyHeight: number = 1.64;
  private playerRoot?: AbstractMesh;

  // IK Controllers for Mirror
  private leftIkController?: BoneIKController;
  private rightIkController?: BoneIKController;
  private leftIkTarget?: AbstractMesh;
  private rightIkTarget?: AbstractMesh;

  // Proxy meshes for mirror mode (fallback/debug)
  private enemyLeftProxy?: Mesh;
  private enemyRightProxy?: Mesh;

  constructor(private scene: Scene) { }

  public setup(models: Record<string, string>, playerUrl?: string, enemyUrl?: string, enemyHeightM: number = 1.64): void {
    this.setupLights();
    this.setupSkyAndGround();
    this.createCanyonRocks();
    this.createPlayerHands();

    if (playerUrl && models[playerUrl]) {
      this.loadPlayerModel(models[playerUrl]);
    }

    if (enemyUrl && models[enemyUrl]) {
      this.enemyHeight = enemyHeightM;
      this.loadEnemyModel(models[enemyUrl], enemyHeightM);
    }
  }

  private loadPlayerModel(url: string): void {
    SceneLoader.ImportMeshAsync("", url, "", this.scene).then((result) => {
      this.playerRoot = result.meshes[0];
      this.playerRoot.position = new Vector3(0, -100, 0); // Hide initially until synced
      // Rotated to look forward (away from camera viewpoint initially).
      this.playerRoot.rotationQuaternion = Quaternion.Identity();

      // Scale it correctly assuming it's roughly 1.75m but models might be larger. We'll use 1:1 scale for now, assuming standard VRM scale.
      this.playerRoot.scaling = new Vector3(1, 1, 1);

      // Ocultar cabezas para que no bloquee la vista desde dentro del casco
      result.meshes.forEach(m => {
        const name = m.name.toLowerCase();
        if (name.includes("head") || name.includes("face") || name.includes("hair") || name.includes("eye") || name.includes("teeth")) {
          m.isVisible = false;
        }
      });
    });
  }

  public getPlayerRoot(): AbstractMesh | undefined {
    return this.playerRoot;
  }

  public getEnemyRoot(): AbstractMesh | undefined {
    return this.enemyRoot;
  }

  private setupLights(): void {
    const ambient = new HemisphericLight("ambient", new Vector3(0, 1, 0), this.scene);
    ambient.intensity = 0.55;
    ambient.diffuse = new Color3(0.85, 0.65, 0.45);
    ambient.groundColor = new Color3(0.25, 0.15, 0.08);

    const sun = new DirectionalLight("sun", new Vector3(-0.6, -1.2, 1.0), this.scene);
    sun.intensity = 1.1;
    sun.diffuse = new Color3(1.0, 0.72, 0.38);

    const fill = new HemisphericLight("fill", new Vector3(0, -1, 0), this.scene);
    fill.intensity = 0.25;
    fill.diffuse = new Color3(0.3, 0.45, 0.7);
  }

  private setupSkyAndGround(): void {
    this.scene.clearColor = new Color4(0.55, 0.38, 0.22, 1);

    const ground = MeshBuilder.CreateGround("ground", { width: 300, height: 300, subdivisions: 8 }, this.scene);
    const groundMat = new StandardMaterial("groundMat", this.scene);
    groundMat.diffuseColor = new Color3(0.32, 0.22, 0.14);
    ground.material = groundMat;
  }

  private createCanyonRocks(): void {
    const rockPositions = [
      { x: -30, y: 0, z: 60, w: 8, h: 28, d: 10 },
      { x: 30, y: 0, z: 60, w: 8, h: 28, d: 10 },
      { x: 0, y: 0, z: 80, w: 20, h: 18, d: 15 },
      { x: -60, y: 0, z: 20, w: 15, h: 40, d: 20 },
      { x: 60, y: 0, z: 20, w: 15, h: 40, d: 20 },
    ];

    const rockMat = new StandardMaterial("rockMat", this.scene);
    rockMat.diffuseColor = new Color3(0.38, 0.26, 0.16);

    rockPositions.forEach((r, i) => {
      const rock = MeshBuilder.CreateBox(`rock${i}`, { width: r.w, height: r.h, depth: r.d }, this.scene);
      rock.position = new Vector3(r.x, r.h / 2 - 0.5, r.z);
      rock.material = rockMat;
    });
  }

  private loadEnemyModel(url: string, targetHeightM: number): void {
    const fallback = this.scene.getMeshByName("enemy");
    SceneLoader.ImportMeshAsync("", url, "", this.scene).then((result) => {
      if (fallback) fallback.isVisible = false;

      this.enemyRoot = result.meshes[0];
      if (result.skeletons && result.skeletons.length > 0) {
        this.enemySkeleton = result.skeletons[0];
        console.log(`[Environment] Enemy skeleton found: "${this.enemySkeleton.name}" with ${this.enemySkeleton.bones.length} bones.`);
        // Log bone names for debugging if needed
        // console.log("Bones:", this.enemySkeleton.bones.map(b => b.name).join(", "));
        this.setupIK(this.enemyRoot, this.enemySkeleton);
      }

      // Calcular altura real del modelo usando bounding box
      let min = new Vector3(Number.MAX_VALUE, Number.MAX_VALUE, Number.MAX_VALUE);
      let max = new Vector3(Number.MIN_VALUE, Number.MIN_VALUE, Number.MIN_VALUE);

      result.meshes.forEach(m => {
        if (m instanceof AbstractMesh && m.getBoundingInfo) {
          const bounds = m.getBoundingInfo().boundingBox;
          min = Vector3.Minimize(min, bounds.minimumWorld);
          max = Vector3.Maximize(max, bounds.maximumWorld);
        }
      });

      const currentHeight = max.y - min.y;

      let yOffset = 0;
      if (currentHeight > 0) {
        // Escalar para que coincida exactamente con targetHeightM
        const finalScale = targetHeightM / currentHeight;
        this.enemyRoot.scaling = new Vector3(finalScale, finalScale, finalScale);
        yOffset = -min.y * finalScale; // Ajustar por si el pivot está en el medio del cuerpo
        console.log(`[Environment] Enemy height: ${currentHeight.toFixed(2)}m -> Scaled to: ${targetHeightM}m (Factor: ${finalScale.toFixed(4)})`);
      } else {
        // Fallback si no hay altura (raro)
        this.enemyRoot.scaling = new Vector3(1, 1, 1);
      }

      if (this.enemyRoot) {
        this.enemyRoot.position = new Vector3(0, yOffset, 3); // A 3 metros de distancia para verse como espejo cercano
        this.enemyRoot.rotationQuaternion = null; // Forza usar Euler para Alien
        this.enemyRoot.rotation = new Vector3(0, Math.PI, 0); // Cara al jugador
      }

      this.createEnemyProxies();
    });
  }

  private setupIK(rootMesh: AbstractMesh, skeleton: Skeleton): void {
    let skinnedMesh = rootMesh.getChildMeshes().find(m => m.skeleton === skeleton) || rootMesh;

    this.leftIkTarget = MeshBuilder.CreateSphere("leftIkTarget", { diameter: 0.1 }, this.scene);
    this.leftIkTarget.isVisible = false;
    this.rightIkTarget = MeshBuilder.CreateSphere("rightIkTarget", { diameter: 0.1 }, this.scene);
    this.rightIkTarget.isVisible = false;

    // Buscar antebrazos por nombre (funciona con cualquier modelo humanoid)
    let leftArmBone = skeleton.bones.find(b =>
      b.name.toLowerCase().includes("leftforearm") ||
      b.name.toLowerCase().includes("l_forearm") ||
      b.name.toLowerCase().includes("forearm_l") ||
      b.name.toLowerCase().includes("left_forearm")
    );
    let rightArmBone = skeleton.bones.find(b =>
      b.name.toLowerCase().includes("rightforearm") ||
      b.name.toLowerCase().includes("r_forearm") ||
      b.name.toLowerCase().includes("forearm_r") ||
      b.name.toLowerCase().includes("right_forearm")
    );

    // Fallback para manos si no encuentra antebrazos
    if (!leftArmBone) {
      leftArmBone = skeleton.bones.find(b =>
        b.name.toLowerCase().includes("lefthand") ||
        b.name.toLowerCase().includes("l_hand") ||
        b.name.toLowerCase().includes("left_hand")
      );
    }
    if (!rightArmBone) {
      rightArmBone = skeleton.bones.find(b =>
        b.name.toLowerCase().includes("righthand") ||
        b.name.toLowerCase().includes("r_hand") ||
        b.name.toLowerCase().includes("right_hand")
      );
    }

    // Fallback específico para Dummy: índices CORRECTOS
    if (!leftArmBone && skeleton.bones.length >= 36) {
      leftArmBone = skeleton.bones[11];  // mixamorig:LeftForeArm
      rightArmBone = skeleton.bones[35]; // mixamorig:RightForeArm
      console.warn("[IK] Usando fallback de índices para modelo Dummy");
    }

    if (!leftArmBone || !rightArmBone) {
      console.error("[IK] No se pudieron encontrar huesos de brazo", {
        leftArmBone: leftArmBone?.name,
        rightArmBone: rightArmBone?.name,
        totalBones: skeleton.bones.length
      });
      return;
    }

    // Prueba C: Eje Y para flexión frontal (Plano X-Z)
    if (leftArmBone) {
      // Espejado: Tu mano IZQUIERDA controla el brazo DERECHO del modelo
      this.leftIkController = new BoneIKController(skinnedMesh, rightArmBone, {
        targetMesh: this.leftIkTarget,
        poleAngle: Math.PI / 2,
        bendAxis: new Vector3(0, 1, 0)
      });
      this.leftIkController.maxAngle = Math.PI;
    }

    if (rightArmBone) {
      // Espejado: Tu mano DERECHA controla el brazo IZQUIERDO del modelo
      this.rightIkController = new BoneIKController(skinnedMesh, leftArmBone, {
        targetMesh: this.rightIkTarget,
        poleAngle: Math.PI / 2,
        bendAxis: new Vector3(0, 1, 0)
      });
      this.rightIkController.maxAngle = Math.PI;
    }

    this.scene.onBeforeRenderObservable.add(() => {
      if (this.leftIkController) this.leftIkController.update();
      if (this.rightIkController) this.rightIkController.update();
    });
  }


  private createPlayerHands(): void {
    const handMat = new StandardMaterial("handMat", this.scene);
    handMat.diffuseColor = new Color3(0.88, 0.72, 0.58);

    this.leftPalmMesh = MeshBuilder.CreateBox("leftHand", { width: 0.22, height: 0.06, depth: 0.28 }, this.scene);
    this.leftPalmMesh.position = new Vector3(-0.52, 1.12, 0.55);
    this.leftPalmMesh.material = handMat;
    this.leftPalmMesh.isVisible = false; // Hiding debug box

    this.rightPalmMesh = MeshBuilder.CreateBox("rightHand", { width: 0.22, height: 0.06, depth: 0.28 }, this.scene);
    this.rightPalmMesh.position = new Vector3(0.52, 1.12, 0.55);
    this.rightPalmMesh.material = handMat;
    this.rightPalmMesh.isVisible = false; // Hiding debug box
  }

  public getPlayerHands(): { left?: Mesh, right?: Mesh } {
    return { left: this.leftPalmMesh, right: this.rightPalmMesh };
  }

  private createEnemyProxies(): void {
    const proxyMat = new StandardMaterial("proxyMat", this.scene);
    proxyMat.diffuseColor = new Color3(0, 1, 1); // Cyan para debug
    proxyMat.alpha = 0.6;

    this.enemyLeftProxy = MeshBuilder.CreateSphere("enemyLeftProxy", { diameter: 0.15 }, this.scene);
    this.enemyLeftProxy.material = proxyMat;
    this.enemyLeftProxy.isVisible = false;

    this.enemyRightProxy = MeshBuilder.CreateSphere("enemyRightProxy", { diameter: 0.15 }, this.scene);
    this.enemyRightProxy.material = proxyMat;
    this.enemyRightProxy.isVisible = false;
  }

  /**
   * Actualiza la posición de las "manos" de Vegeta para espejar al jugador.
   */
  public updateEnemyMirror(active: boolean, playerHeadPos: Vector3, playerHeadRot: Quaternion, leftHand: Vector3, rightHand: Vector3): void {
    if (!this.enemyRoot || !active) {
      if (this.enemyLeftProxy) this.enemyLeftProxy.isVisible = false;
      if (this.enemyRightProxy) this.enemyRightProxy.isVisible = false;
      return;
    }

    if (this.enemyLeftProxy) this.enemyLeftProxy.isVisible = true;
    if (this.enemyRightProxy) this.enemyRightProxy.isVisible = true;

    // Calcular posición relativa del jugador: (Mano - Cabeza)
    const relL = leftHand.subtract(playerHeadPos);
    const relR = rightHand.subtract(playerHeadPos);

    // Rotar los vectores relativos según la orientación de la cabeza para que sean "locales"
    const invHeadRot = Quaternion.Inverse(playerHeadRot);
    const localL = new Vector3();
    relL.rotateByQuaternionToRef(invHeadRot, localL);
    const localR = new Vector3();
    relR.rotateByQuaternionToRef(invHeadRot, localR);

    // Vegeta está mirando al jugador (rotado 180 grados en Y)
    // El punto de referencia son los hombros (estimado a ~82% de su altura)
    const enemyRefPoint = this.enemyRoot.position.add(new Vector3(0, this.enemyHeight * 0.82, 0));

    // True Mirror: Tu derecha -> Su izquierda visual
    // Usamos las coordenadas LOCALES (body-relative) calculadas arriba
    if (this.leftIkTarget && this.rightIkTarget) {
      // Altura relativa explícita (Mano - Cabeza)
      const deltaRY = rightHand.y - playerHeadPos.y;
      const deltaLY = leftHand.y - playerHeadPos.y;

      this.leftIkTarget.position = new Vector3(
        this.enemyRoot.position.x + localR.x,
        enemyRefPoint.y + deltaRY,
        this.enemyRoot.position.z - localR.z
      );

      this.rightIkTarget.position = new Vector3(
        this.enemyRoot.position.x + localL.x,
        enemyRefPoint.y + deltaLY,
        this.enemyRoot.position.z - localL.z
      );
    }

    // Proxies visuales para debug
    if (this.enemyLeftProxy && this.leftIkTarget) this.enemyLeftProxy.position = this.leftIkTarget.position;
    if (this.enemyRightProxy && this.rightIkTarget) this.enemyRightProxy.position = this.rightIkTarget.position;
  }
  public getIkTargets(): { left: AbstractMesh, right: AbstractMesh } | null {
    if (this.leftIkTarget && this.rightIkTarget) {
      return { left: this.leftIkTarget, right: this.rightIkTarget };
    }
    return null;
  }
}
