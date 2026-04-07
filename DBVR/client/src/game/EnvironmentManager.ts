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
  Quaternion
} from "@babylonjs/core";
import "@babylonjs/loaders/glTF";

export class EnvironmentManager {
  private leftPalmMesh?: Mesh;
  private rightPalmMesh?: Mesh;
  private enemyRoot?: AbstractMesh;
  private enemySkeleton?: Skeleton;
  private enemyHeight: number = 1.64;
  
  // Proxy meshes for mirror mode (fallback/debug)
  private enemyLeftProxy?: Mesh;
  private enemyRightProxy?: Mesh;

  constructor(private scene: Scene) {}

  public setup(models: Record<string, string>, vegetaUrl?: string, enemyHeightM: number = 1.64): void {
    this.setupLights();
    this.setupSkyAndGround();
    this.createCanyonRocks();
    this.createPlayerHands();
    
    if (vegetaUrl && models[vegetaUrl]) {
        this.enemyHeight = enemyHeightM;
        this.loadEnemyModel(models[vegetaUrl], enemyHeightM);
    }
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
      { x: 30,  y: 0, z: 60, w: 8, h: 28, d: 10 },
      { x: 0,   y: 0, z: 80, w: 20, h: 18, d: 15 },
      { x: -60, y: 0, z: 20, w: 15, h: 40, d: 20 },
      { x: 60,  y: 0, z: 20, w: 15, h: 40, d: 20 },
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
          console.log(`[Environment] Enemy skeleton found with ${this.enemySkeleton.bones.length} bones.`);
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
      
      if (currentHeight > 0) {
        // Escalar para que coincida exactamente con targetHeightM
        const finalScale = targetHeightM / currentHeight;
        this.enemyRoot.scaling = new Vector3(finalScale, finalScale, finalScale);
        console.log(`[Environment] Enemy height: ${currentHeight.toFixed(2)}m -> Scaled to: ${this.enemyHeight}m (Factor: ${finalScale.toFixed(4)})`);
      } else {
        // Fallback si no hay altura (raro)
        this.enemyRoot.scaling = new Vector3(1, 1, 1);
      }

      if (this.enemyRoot) {
        this.enemyRoot.position = new Vector3(0, 0, 15); // A 15 metros del jugador
        this.enemyRoot.rotation = new Vector3(0, Math.PI, 0); // Cara al jugador
      }

      this.createEnemyProxies();
    });
  }

  private createPlayerHands(): void {
    const handMat = new StandardMaterial("handMat", this.scene);
    handMat.diffuseColor = new Color3(0.88, 0.72, 0.58);

    this.leftPalmMesh = MeshBuilder.CreateBox("leftHand", { width: 0.22, height: 0.06, depth: 0.28 }, this.scene);
    this.leftPalmMesh.position = new Vector3(-0.52, 1.12, 0.55);
    this.leftPalmMesh.material = handMat;

    this.rightPalmMesh = MeshBuilder.CreateBox("rightHand", { width: 0.22, height: 0.06, depth: 0.28 }, this.scene);
    this.rightPalmMesh.position = new Vector3(0.52, 1.12, 0.55);
    this.rightPalmMesh.material = handMat;
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
    // Su centro de hombros estimado está a ~1.4m de altura
    const enemyRefPoint = this.enemyRoot.position.add(new Vector3(0, this.enemyHeight * 0.85, 0));

    // Aplicar a Vegeta (invirtiendo X para que sea un espejo)
    // Si muevo mi mano derecha a MI derecha, Vegeta mueve su mano "izquierda" a SU izquierda (que es mi derecha visual)
    const mirrorL = new Vector3(-localL.x, localL.y, -localL.z); 
    const mirrorR = new Vector3(-localR.x, localR.y, -localR.z);

    const worldL = enemyRefPoint.add(mirrorL);
    const worldR = enemyRefPoint.add(mirrorR);

    if (this.enemyLeftProxy) this.enemyLeftProxy.position = worldL;
    if (this.enemyRightProxy) this.enemyRightProxy.position = worldR;

    // Intentar mover huesos si hay esqueleto
    if (this.enemySkeleton) {
        // Nombres comunes de Mixamo/Vroid
        const leftHandBone = this.enemySkeleton.bones.find(b => b.name.toLowerCase().includes("lefthand") || b.name.toLowerCase().includes("l_hand"));
        const rightHandBone = this.enemySkeleton.bones.find(b => b.name.toLowerCase().includes("righthand") || b.name.toLowerCase().includes("r_hand"));

        if (leftHandBone) leftHandBone.setAbsolutePosition(worldL, this.enemyRoot);
        if (rightHandBone) rightHandBone.setAbsolutePosition(worldR, this.enemyRoot);
    }
  }
}
