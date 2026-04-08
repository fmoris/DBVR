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
  Mesh,
  CylinderParticleEmitter,
  PointLight,
} from "@babylonjs/core";

export interface Vec3 { x: number; y: number; z: number; }

export type AttackType = string;

export class VFXManager {
  private chargeMesh: Mesh | null = null;
  private chargePS: ParticleSystem | null = null;
  private chargeLight: PointLight | null = null;
  private blockShield: Mesh | null = null;
  private scene: Scene;

  constructor(scene: Scene) {
    this.scene = scene;
  }

  // ============================================
  // ATAQUES DE KI
  // ============================================
  
  spawnKiProjectile(from: Vec3, to: Vec3, type: "basic" | "charged", onImpact?: () => void): void {
    const isCharged = type === "charged";
    const size = isCharged ? 0.5 : 0.25;
    const speed = isCharged ? 0.8 : 1.5;
    const color = isCharged 
      ? { r: 0.8, g: 0.4, b: 0.1 }  // Naranja para cargado
      : { r: 0.2, g: 0.6, b: 1.0 }; // Azul para básico

    // Esfera principal
    const ball = MeshBuilder.CreateSphere("ki_ball", { diameter: size }, this.scene);
    ball.position = new Vector3(from.x, from.y, from.z);

    const mat = new StandardMaterial("ki_mat", this.scene);
    mat.diffuseColor = new Color3(color.r, color.g, color.b);
    mat.emissiveColor = new Color3(color.r * 0.5, color.g * 0.5, color.b * 0.5);
    mat.specularColor = new Color3(1, 1, 1);
    mat.alpha = 0.85;
    ball.material = mat;

    // Efectos de partículas
    const ps = new ParticleSystem("ki_ps", 200, this.scene);
    ps.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    ps.emitter = ball;
    ps.minEmitBox = new Vector3(-0.1, -0.1, -0.1);
    ps.maxEmitBox = new Vector3(0.1, 0.1, 0.1);
    ps.color1 = new Color4(color.r, color.g, color.b, 0.9);
    ps.color2 = new Color4(color.r * 0.5, color.g * 0.5, color.b, 0.5);
    ps.minSize = 0.04;
    ps.maxSize = isCharged ? 0.2 : 0.12;
    ps.minLifeTime = 0.1;
    ps.maxLifeTime = 0.4;
    ps.emitRate = isCharged ? 200 : 150;
    ps.minEmitPower = 1;
    ps.maxEmitPower = isCharged ? 5 : 3;
    ps.updateSpeed = 0.015;
    ps.start();

    // Trail de partículas (más largo para cargado)
    if (isCharged) {
      const trail = new ParticleSystem("trail", 100, this.scene);
      trail.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
      trail.emitter = ball;
      trail.minEmitBox = new Vector3(0, 0, 0);
      trail.maxEmitBox = new Vector3(0, 0, 0);
      trail.color1 = new Color4(1, 0.6, 0.2, 0.7);
      trail.color2 = new Color4(1, 0.3, 0.0, 0.4);
      trail.minSize = 0.08;
      trail.maxSize = 0.25;
      trail.minLifeTime = 0.3;
      trail.maxLifeTime = 0.6;
      trail.emitRate = 80;
      trail.minEmitPower = 0;
      trail.maxEmitPower = 0;
      trail.updateSpeed = 0.02;
      trail.direction1 = new Vector3(0, 0, -1);
      trail.direction2 = new Vector3(0, 0, -1);
      trail.minEmitPower = 2;
      trail.maxEmitPower = 4;
      trail.start();
    }

    // Animación de vuelo
    const totalFrames = Math.floor(60 / speed);

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
      this.spawnImpact(to, isCharged ? "charged" : "basic");
      ps.stop();
      if (isCharged && this.scene.getMeshByName("trail")) {
        // Limpiar trail
      }
      ball.dispose();
      onImpact?.();
    });
  }

  spawnKamehameha(from: Vec3, to: Vec3, chargeTime: number, onImpact?: () => void): void {
    const fromVec = new Vector3(from.x, from.y, from.z);
    // Beam principal
    const beam = MeshBuilder.CreateCylinder("kamehameha", {
      height: 18,
      diameterTop: 0.3 + chargeTime * 0.15,
      diameterBottom: 0.8 + chargeTime * 0.2,
      tessellation: 16,
    }, this.scene);
    
    beam.position = fromVec.add(new Vector3(0, 0, 9));
    beam.rotation.x = Math.PI / 2;

    const beamMat = new StandardMaterial("beamMat", this.scene);
    beamMat.diffuseColor = new Color3(0.2, 0.6, 1.0);
    beamMat.emissiveColor = new Color3(0.1, 0.4, 0.9);
    beamMat.alpha = 0.7;
    beamMat.specularColor = new Color3(1, 1, 1);
    beam.material = beamMat;

    // Partículas de energía azul
    const ps = new ParticleSystem("kamehameha_ps", 500, this.scene);
    ps.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    ps.emitter = fromVec;
    ps.minEmitBox = new Vector3(-0.3, -0.3, 0);
    ps.maxEmitBox = new Vector3(0.3, 0.3, 0);
    ps.color1 = new Color4(0.3, 0.8, 1.0, 1.0);
    ps.color2 = new Color4(0.1, 0.5, 1.0, 0.6);
    ps.colorDead = new Color4(0, 0.2, 0.5, 0);
    ps.minSize = 0.15;
    ps.maxSize = 0.4 + chargeTime * 0.1;
    ps.minLifeTime = 0.5;
    ps.maxLifeTime = 1.2;
    ps.emitRate = 300;
    ps.minEmitPower = 15;
    ps.maxEmitPower = 25;
    ps.updateSpeed = 0.01;
    ps.direction1 = new Vector3(-0.2, -0.2, 1);
    ps.direction2 = new Vector3(0.2, 0.2, 1);
    ps.start();

    // Efecto de electricidad
    const electric = new ParticleSystem("electric", 150, this.scene);
    electric.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    electric.emitter = beam;
    electric.color1 = new Color4(0.8, 0.9, 1.0, 1.0);
    electric.color2 = new Color4(0.5, 0.7, 1.0, 0.5);
    electric.minSize = 0.05;
    electric.maxSize = 0.15;
    electric.minLifeTime = 0.1;
    electric.maxLifeTime = 0.3;
    electric.emitRate = 100;
    electric.minEmitPower = 5;
    electric.maxEmitPower = 10;
    electric.start();

    // Animación de avance
    const animBeam = new Animation(
      "beam_anim", "scaling.z", 60,
      Animation.ANIMATIONTYPE_FLOAT,
      Animation.ANIMATIONLOOPMODE_CONSTANT
    );
    
    const frames = 45;
    
    beam.scaling.z = 0;
    animBeam.setKeys([
      { frame: 0, value: 0 },
      { frame: frames, value: 1 },
    ]);
    beam.animations = [animBeam];

    this.scene.beginAnimation(beam, 0, frames, false, 1, () => {
      this.spawnImpact(to, "kamehameha");
      ps.stop();
      electric.stop();
      
      setTimeout(() => {
        beam.dispose();
        ps.dispose();
        electric.dispose();
      }, 500);
      
      onImpact?.();
    });
  }

  spawnFinalFlash(from: Vec3, to: Vec3, chargeTime: number, onImpact?: () => void): void {
    // Beam más ancho y diferente forma (V)
    const beam = MeshBuilder.CreateCylinder("finalFlash", {
      height: 18,
      diameterTop: 0.5 + chargeTime * 0.2,
      diameterBottom: 1.2 + chargeTime * 0.3,
      tessellation: 24,
    }, this.scene);
    
    const fromVec = new Vector3(from.x, from.y, from.z);
    beam.position = fromVec.add(new Vector3(0, 0, 9));
    beam.rotation.x = Math.PI / 2;

    const beamMat = new StandardMaterial("ffMat", this.scene);
    beamMat.diffuseColor = new Color3(1.0, 0.8, 0.2);
    beamMat.emissiveColor = new Color3(1.0, 0.6, 0.0);
    beamMat.alpha = 0.8;
    beamMat.specularColor = new Color3(1, 1, 0.5);
    beam.material = beamMat;

    // Partículas doradas
    const ps = new ParticleSystem("finalFlash_ps", 800, this.scene);
    ps.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    ps.emitter = fromVec;
    ps.minEmitBox = new Vector3(-0.5, -0.5, 0);
    ps.maxEmitBox = new Vector3(0.5, 0.5, 0);
    ps.color1 = new Color4(1.0, 0.9, 0.3, 1.0);
    ps.color2 = new Color4(1.0, 0.6, 0.0, 0.7);
    ps.colorDead = new Color4(1.0, 0.3, 0.0, 0);
    ps.minSize = 0.2;
    ps.maxSize = 0.5 + chargeTime * 0.15;
    ps.minLifeTime = 0.6;
    ps.maxLifeTime = 1.5;
    ps.emitRate = 500;
    ps.minEmitPower = 20;
    ps.maxEmitPower = 35;
    ps.updateSpeed = 0.008;
    ps.direction1 = new Vector3(-0.3, -0.3, 1);
    ps.direction2 = new Vector3(0.3, 0.3, 1);
    ps.start();

    // Efecto de explode
    const explode = new ParticleSystem("explode", 300, this.scene);
    explode.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    explode.emitter = new Vector3(to.x, to.y, to.z);
    explode.minEmitBox = new Vector3(-1, -1, -1);
    explode.maxEmitBox = new Vector3(1, 1, 1);
    explode.color1 = new Color4(1.0, 1.0, 0.5, 1.0);
    explode.color2 = new Color4(1.0, 0.5, 0.0, 0.8);
    explode.minSize = 0.3;
    explode.maxSize = 0.8;
    explode.minLifeTime = 0.3;
    explode.maxLifeTime = 0.8;
    explode.emitRate = 1000;
    explode.minEmitPower = 10;
    explode.maxEmitPower = 25;
    explode.targetStopDuration = 0.3;
    explode.disposeOnStop = true;

    // Animación
    const frames = 50;
    beam.scaling.z = 0;
    const animBeam = new Animation("ff_anim", "scaling.z", 60, Animation.ANIMATIONTYPE_FLOAT);
    animBeam.setKeys([
      { frame: 0, value: 0 },
      { frame: frames, value: 1 },
    ]);
    beam.animations = [animBeam];

    this.scene.beginAnimation(beam, 0, frames, false, 1, () => {
      explode.start();
      ps.stop();
      
      setTimeout(() => {
        beam.dispose();
        ps.dispose();
      }, 800);
      
      onImpact?.();
    });
  }

  // ============================================
  // EFECTOS DE IMPACTO
  // ============================================
  public spawnImpact(pos: Vec3, type: string): void {
    const colors: Record<string, any> = {
      basic: { c1: new Color4(0.5, 0.9, 1.0, 1.0), c2: new Color4(1.0, 1.0, 1.0, 0.8) },
      charged: { c1: new Color4(1.0, 0.7, 0.3, 1.0), c2: new Color4(1.0, 0.4, 0.0, 0.8) },
      kamehameha: { c1: new Color4(0.3, 0.8, 1.0, 1.0), c2: new Color4(0.1, 0.5, 1.0, 0.6) },
      finalFlash: { c1: new Color4(1.0, 0.9, 0.3, 1.0), c2: new Color4(1.0, 0.5, 0.0, 0.8) },
    };

    const c = colors[type] || colors.charged;
    const intensity = type === "finalFlash" ? 2 : type === "kamehameha" ? 1.5 : 1;

    const impact = new ParticleSystem("impact", Math.floor(300 * intensity), this.scene);
    impact.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    impact.emitter = new Vector3(pos.x, pos.y, pos.z);
    impact.minEmitBox = new Vector3(-0.3, -0.3, -0.3);
    impact.maxEmitBox = new Vector3(0.3, 0.3, 0.3);
    impact.color1 = c.c1;
    impact.color2 = c.c2;
    impact.minSize = 0.1 * intensity;
    impact.maxSize = 0.4 * intensity;
    impact.minLifeTime = 0.2;
    impact.maxLifeTime = 0.6;
    impact.emitRate = 500 * intensity;
    impact.minEmitPower = 5 * intensity;
    impact.maxEmitPower = 15 * intensity;
    impact.updateSpeed = 0.015;
    impact.targetStopDuration = 0.2;
    impact.disposeOnStop = true;
    impact.start();
  }

  // ============================================
  // EFECTOS DE CARGA
  // ============================================
  showChargeEffect(active: boolean, type: string = "normal", position?: Vector3): void {
    if (!active) {
      if (this.chargeMesh) {
        this.chargeMesh.dispose();
        this.chargeMesh = null;
      }
      if (this.chargePS) {
        this.chargePS.stop();
        this.chargePS.dispose();
        this.chargePS = null;
      }
      if (this.chargeLight) {
        this.chargeLight.dispose();
        this.chargeLight = null;
      }
      return;
    }

    // Crear esfera de carga alrededor de la mano o posición centrada
    this.chargeMesh = MeshBuilder.CreateSphere("charge", { diameter: 0.15 }, this.scene);
    if (position) {
        this.chargeMesh.position.copyFrom(position);
    } else {
        this.chargeMesh.position.set(0.3, 1.4, 0.5);
    }

    // Luz de carga
    this.chargeLight = new PointLight("chargeLight", this.chargeMesh.position, this.scene);
    this.chargeLight.intensity = 0;
    this.chargeLight.range = 5;

    const mat = new StandardMaterial("chargeMat", this.scene);
    if (type === "kamehameha") {
      mat.diffuseColor = new Color3(0.2, 0.5, 1.0);
      mat.emissiveColor = new Color3(0.1, 0.3, 0.8);
      this.chargeLight.diffuse = new Color3(0.4, 0.6, 1.0);
    } else if (type === "finalFlash") {
      mat.diffuseColor = new Color3(1.0, 0.7, 0.2);
      mat.emissiveColor = new Color3(0.8, 0.4, 0.0);
      this.chargeLight.diffuse = new Color3(1.0, 0.8, 0.3);
    } else {
      mat.diffuseColor = new Color3(0.8, 0.4, 0.1);
      mat.emissiveColor = new Color3(0.5, 0.2, 0.0);
      this.chargeLight.diffuse = new Color3(1.0, 0.5, 0.2);
    }
    mat.alpha = 0.7;
    this.chargeMesh.material = mat;

    // Animación de pulsación
    const pulse = new Animation("pulse", "scaling", 60, Animation.ANIMATIONTYPE_VECTOR3);
    pulse.setKeys([
      { frame: 0, value: new Vector3(1, 1, 1) },
      { frame: 15, value: new Vector3(1.3, 1.3, 1.3) },
      { frame: 30, value: new Vector3(1, 1, 1) },
    ]);
    this.chargeMesh.animations = [pulse];
    this.scene.beginAnimation(this.chargeMesh, 0, 30, true);

    // Partículas de carga
    this.chargePS = new ParticleSystem("charge_ps", 100, this.scene);
    this.chargePS.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    this.chargePS.emitter = this.chargeMesh;
    this.chargePS.color1 = new Color4(1, 0.6, 0.2, 0.8);
    this.chargePS.color2 = new Color4(1, 0.3, 0.0, 0.5);
    this.chargePS.minSize = 0.03;
    this.chargePS.maxSize = 0.08;
    this.chargePS.minLifeTime = 0.2;
    this.chargePS.maxLifeTime = 0.5;
    this.chargePS.emitRate = 60;
    this.chargePS.minEmitPower = 0.5;
    this.chargePS.maxEmitPower = 1.5;
    this.chargePS.start();
  }

  /**
   * Actualiza la intensidad de los efectos de carga (Phase 13)
   * @param elapsed Segundos transcurridos cargando
   * @param position Nueva posición (opcional, para seguimiento)
   * @param targetTime Tiempo objetivo para carga completa (Phase 16)
   */
  updateChargeEffect(elapsed: number, type: string, position?: Vector3, targetTime: number = 2.0): void {
    const progress = Math.min(1.0, elapsed / targetTime);
    
    if (this.chargeMesh && position) {
        this.chargeMesh.position.copyFrom(position);
    }

    if (this.chargeLight) {
        if (position) this.chargeLight.position.copyFrom(position);
        
        if (progress >= 1.0) {
            const overCharge = elapsed - targetTime;
            this.chargeLight.intensity = Math.min(5.0, 1.0 + overCharge * 2.0);
            this.chargeLight.range = 8 + Math.min(12, overCharge * 4);
        } else {
            this.chargeLight.intensity = progress * 1.5; // Aumentado para mayor visibilidad
            this.chargeLight.range = 3 + progress * 4;
        }
    }
    
    if (this.chargeMesh) {
        // Phase 17: La esfera empieza casi invisible (0.01) y crece al 100% (1.2 para especiales grandes)
        const maxScale = (type === "genkidama" || type === "finalFlash") ? 1.5 : 1.0;
        const baseScale = 0.01 + (maxScale * progress); 
        const pulse = progress >= 1.0 ? (Math.sin(elapsed * 12) * 0.1) : 0;
        const s = baseScale + pulse;
        this.chargeMesh.scaling.set(s, s, s);

        // Iluminación progresiva del material (Emisión)
        const mat = this.chargeMesh.material as StandardMaterial;
        if (mat) {
            const intensity = 0.1 + (progress * 0.9); // De tenue a intenso
            if (type === "kamehameha" || type === "normal") {
                mat.emissiveColor.set(0.1 * intensity, 0.4 * intensity, 1.0 * intensity);
            } else if (type === "finalFlash" || type === "genkidama") {
                mat.emissiveColor.set(1.0 * intensity, 0.8 * intensity, 0.2 * intensity);
            } else {
                mat.emissiveColor.set(intensity, intensity * 0.5, 0);
            }
        }
    }
  }

  // ============================================
  // DEFENSAS
  // ============================================
  showBlockShield(active: boolean): void {
    if (!active) {
      if (this.blockShield) {
        this.blockShield.dispose();
        this.blockShield = null;
      }
      return;
    }

    // Escudo hexagonal frente al jugador
    this.blockShield = MeshBuilder.CreateDisc("shield", { radius: 0.8, tessellation: 6 }, this.scene);
    this.blockShield.position = new Vector3(0, 1.5, 1.2);
    this.blockShield.rotation.y = Math.PI;

    const mat = new StandardMaterial("shieldMat", this.scene);
    mat.diffuseColor = new Color3(0.2, 0.6, 1.0);
    mat.emissiveColor = new Color3(0.1, 0.3, 0.6);
    mat.alpha = 0.4;
    mat.backFaceCulling = false;
    this.blockShield.material = mat;

    // Animación de aparición
    this.blockShield.scaling = new Vector3(0, 0, 0);
    const scaleAnim = new Animation("shield_scale", "scaling", 60, Animation.ANIMATIONTYPE_VECTOR3);
    scaleAnim.setKeys([
      { frame: 0, value: new Vector3(0, 0, 0) },
      { frame: 10, value: new Vector3(1.2, 1.2, 1.2) },
      { frame: 15, value: new Vector3(1, 1, 1) },
    ]);
    this.blockShield.animations = [scaleAnim];
    this.scene.beginAnimation(this.blockShield, 0, 15, false);
  }

  showDodgeEffect(): void {
    // Estela de movimiento rápido
    const dodge = new ParticleSystem("dodge", 50, this.scene);
    dodge.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    dodge.emitter = new Vector3(0, 1.5, 0.8);
    dodge.minEmitBox = new Vector3(-0.3, -0.5, -0.2);
    dodge.maxEmitBox = new Vector3(0.3, 0.5, 0.2);
    dodge.color1 = new Color4(0.5, 0.8, 1.0, 0.8);
    dodge.color2 = new Color4(0.2, 0.5, 0.8, 0.5);
    dodge.minSize = 0.05;
    dodge.maxSize = 0.15;
    dodge.minLifeTime = 0.1;
    dodge.maxLifeTime = 0.3;
    dodge.emitRate = 300;
    dodge.targetStopDuration = 0.15;
    dodge.disposeOnStop = true;
    dodge.direction1 = new Vector3(-1, 0, 0);
    dodge.direction2 = new Vector3(1, 0, 0);
    dodge.minEmitPower = 3;
    dodge.maxEmitPower = 8;
    dodge.start();
  }

  showDeflectEffect(): void {
    // Efecto de redirección de energía
    const deflect = new ParticleSystem("deflect", 100, this.scene);
    deflect.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    deflect.emitter = new Vector3(0, 1.5, 1);
    deflect.color1 = new Color4(0.8, 1.0, 0.5, 1.0);
    deflect.color2 = new Color4(0.5, 0.8, 0.3, 0.6);
    deflect.minSize = 0.08;
    deflect.maxSize = 0.2;
    deflect.minLifeTime = 0.2;
    deflect.maxLifeTime = 0.5;
    deflect.emitRate = 200;
    deflect.direction1 = new Vector3(-1, 0.5, 1);
    deflect.direction2 = new Vector3(1, -0.5, 1);
    deflect.minEmitPower = 5;
    deflect.maxEmitPower = 12;
    deflect.targetStopDuration = 0.3;
    deflect.disposeOnStop = true;
    deflect.start();
  }

  // ============================================
  // AURAS Y EFECTOS AMBIENTALES
  // ============================================
  /**
   * Crea un aura de Ki persistente para un personaje.
   */
  public createAura(name: string, emitter: Mesh | Vector3): ParticleSystem {
    const ps = new ParticleSystem(name, 500, this.scene);
    ps.particleTexture = new Texture("https://assets.babylonjs.com/textures/flare.png", this.scene);
    ps.emitter = emitter;
    
    // Configurar emisor cilíndrico para crear un "anillo" de energía
    // Esto deja el centro (la visión) más despejada
    const cylinderEmitter = new CylinderParticleEmitter();
    cylinderEmitter.radius = 1.2;
    cylinderEmitter.height = 2.0;
    cylinderEmitter.radiusRange = 0.4; // Emite en un anillo de 0.8 a 1.2
    ps.particleEmitterType = cylinderEmitter;
    
    ps.color1 = new Color4(0.3, 0.6, 1.0, 0.4);
    ps.color2 = new Color4(1.0, 1.0, 1.0, 0.2);
    ps.colorDead = new Color4(0, 0, 0.5, 0);

    ps.minSize = 0.1;
    ps.maxSize = 0.4;
    ps.minLifeTime = 0.5;
    ps.maxLifeTime = 1.0;
    ps.emitRate = 0; // Empieza apagada
    
    ps.direction1 = new Vector3(-0.1, 1, -0.1);
    ps.direction2 = new Vector3(0.1, 1, 0.1);
    ps.minEmitPower = 1;
    ps.maxEmitPower = 3;
    ps.updateSpeed = 0.01;
    
    ps.start();
    return ps;
  }

  /**
   * Actualiza la intensidad del aura según el % de Ki y estado de carga.
   */
  public updateAura(ps: ParticleSystem, kiPercent: number, isCharging: boolean, npBase: number = 1000, customColor?: Color4): void {
    if (kiPercent <= 0) {
      ps.emitRate = 0;
      return;
    }

    // Usar color personalizado si se provee, si no, lógica por NP
    if (customColor) {
      ps.color1 = new Color4(customColor.r, customColor.g, customColor.b, 0.4);
      ps.color2 = new Color4(customColor.r * 1.2, customColor.g * 1.2, customColor.b * 1.2, 0.15);
    } else {
      // El color cambia ligeramente según el NP (más blanco/amarillo si es muy poderoso)
      if (npBase > 5000) {
        ps.color1 = new Color4(1.0, 0.9, 0.4, 0.4); // Dorado semitransparente
      } else {
        ps.color1 = new Color4(0.3, 0.7, 1.0, 0.4); // Azul semitransparente
      }
      ps.color2 = new Color4(1, 1, 1, 0.15);
    }

    // Escalado de intensidad
    const chargeMultiplier = isCharging ? 2.5 : 1.0;
    ps.emitRate = (100 + kiPercent * 3) * chargeMultiplier;
    ps.minSize = 0.1 + (kiPercent / 100) * 0.2;
    ps.maxSize = 0.3 + (kiPercent / 100) * 0.5;
    
    // Si carga, las partículas suben más rápido y errático
    ps.minEmitPower = isCharging ? 4 : 1;
    ps.maxEmitPower = isCharging ? 8 : 3;
    ps.updateSpeed = isCharging ? 0.02 : 0.01;
  }
}