import {
  Scene,
  MeshBuilder,
  StandardMaterial,
  Color3,
  Color4,
  Vector3,
  ParticleSystem,
  Texture,
  Animation,
} from "@babylonjs/core";

interface Vec3 { x: number; y: number; z: number; }

export class VFXManager {
  constructor(private scene: Scene) {}

  spawnProjectile(from: Vec3, to: Vec3, onImpact?: () => void): void {
    // Esfera del proyectil
    const ball = MeshBuilder.CreateSphere("ki_ball", { diameter: 0.35 }, this.scene);
    ball.position = new Vector3(from.x, from.y, from.z);

    const mat = new StandardMaterial("ki_mat", this.scene);
    mat.diffuseColor = new Color3(0.2, 0.6, 1.0);
    mat.emissiveColor = new Color3(0.1, 0.4, 1.0);
    mat.specularColor = new Color3(1, 1, 1);
    ball.material = mat;

    // Particulas alrededor del proyectil
    const ps = new ParticleSystem("ki_ps", 150, this.scene);
    ps.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    ps.emitter = ball;
    ps.minEmitBox = new Vector3(-0.1, -0.1, -0.1);
    ps.maxEmitBox = new Vector3(0.1, 0.1, 0.1);
    ps.color1 = new Color4(0.4, 0.8, 1.0, 0.9);
    ps.color2 = new Color4(0.1, 0.3, 1.0, 0.5);
    ps.minSize = 0.04;
    ps.maxSize = 0.15;
    ps.minLifeTime = 0.1;
    ps.maxLifeTime = 0.3;
    ps.emitRate = 120;
    ps.minEmitPower = 1;
    ps.maxEmitPower = 3;
    ps.updateSpeed = 0.02;
    ps.start();

    // Animacion de vuelo
    const totalFrames = 40;
    const anim = new Animation(
      "ki_move", "position", 60,
      Animation.ANIMATIONTYPE_VECTOR3,
      Animation.ANIMATIONLOOPMODE_CONSTANT
    );
    anim.setKeys([
      { frame: 0, value: new Vector3(from.x, from.y, from.z) },
      { frame: totalFrames, value: new Vector3(to.x, to.y, to.z) },
    ]);
    ball.animations = [anim];

    this.scene.beginAnimation(ball, 0, totalFrames, false, 1, () => {
      // Explosion de impacto
      this.spawnImpact(to);
      ps.stop();
      ball.dispose();
      onImpact?.();
    });
  }

  private spawnImpact(pos: Vec3): void {
    const impact = new ParticleSystem("impact", 300, this.scene);
    impact.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    impact.emitter = new Vector3(pos.x, pos.y, pos.z);
    impact.minEmitBox = new Vector3(-0.2, -0.2, -0.2);
    impact.maxEmitBox = new Vector3(0.2, 0.2, 0.2);
    impact.color1 = new Color4(0.5, 0.9, 1.0, 1.0);
    impact.color2 = new Color4(1.0, 1.0, 1.0, 0.8);
    impact.minSize = 0.1;
    impact.maxSize = 0.4;
    impact.minLifeTime = 0.2;
    impact.maxLifeTime = 0.6;
    impact.emitRate = 500;
    impact.minEmitPower = 5;
    impact.maxEmitPower = 15;
    impact.updateSpeed = 0.02;
    impact.targetStopDuration = 0.15;
    impact.disposeOnStop = true;
    impact.start();
  }
}
