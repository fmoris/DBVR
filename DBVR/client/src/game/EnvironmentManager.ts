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
  AbstractMesh
} from "@babylonjs/core";
import "@babylonjs/loaders/glTF";

export class EnvironmentManager {
  private leftPalmMesh?: Mesh;
  private rightPalmMesh?: Mesh;

  constructor(private scene: Scene) {}

  public setup(models: Record<string, string>, vegetaUrl?: string, enemyHeightM: number = 1.64): void {
    this.setupLights();
    this.setupSkyAndGround();
    this.createCanyonRocks();
    this.createPlayerHands();
    
    if (vegetaUrl && models[vegetaUrl]) {
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
      
      const root = result.meshes[0];

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
        root.scaling = new Vector3(finalScale, finalScale, finalScale);
        console.log(`[Environment] Enemy height: ${currentHeight.toFixed(2)}m -> Scaled to: ${targetHeightM}m (Factor: ${finalScale.toFixed(4)})`);
      } else {
        // Fallback si no hay altura (raro)
        root.scaling = new Vector3(1, 1, 1);
      }

      root.position = new Vector3(0, 0, 15); // A 15 metros del jugador
      root.rotation = new Vector3(0, Math.PI, 0); // Cara al jugador
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
}
