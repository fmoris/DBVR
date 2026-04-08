import { Engine, Scene, FreeCamera, Vector3, Color4 } from "@babylonjs/core";

export class GameEngine {
  private engine: Engine;
  private scene: Scene;
  private camera!: FreeCamera;

  constructor(canvas: HTMLCanvasElement) {
    this.engine = new Engine(canvas, true, {
      preserveDrawingBuffer: true,
      stencil: true,
    });
    this.scene = new Scene(this.engine);
    this.scene.clearColor = new Color4(0.02, 0.02, 0.08, 1);

    this.setupCamera();
    this.setupResize();
  }

  private setupCamera(): void {
    this.camera = new FreeCamera("camera", new Vector3(0, 1.7, 0), this.scene);
    this.camera.setTarget(new Vector3(0, 1.7, 10));
    this.camera.minZ = 0.1;
  }

  private setupResize(): void {
    window.addEventListener("resize", () => {
      this.engine.resize();
    });
  }

  public runRenderLoop(renderFn?: () => void): void {
    this.engine.runRenderLoop(() => {
      if (renderFn) renderFn();
      this.scene.render();
    });
  }

  public getScene(): Scene {
    return this.scene;
  }

  public getEngine(): Engine {
    return this.engine;
  }

  public getCamera(): FreeCamera {
    return this.camera;
  }

  public dispose(): void {
    this.engine.dispose();
  }
}
