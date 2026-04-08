/**
 * VFXManager
 * Gestiona efectos visuales, partículas y proyectiles de KI
 */

import * as BABYLON from '@babylonjs/core';
import { Projectile } from '../types';

export class VFXManager {
  private projectiles: Map<string, Projectile> = new Map();
  private projectileMeshes: Map<string, BABYLON.Mesh> = new Map();
  private particleSystems: BABYLON.ParticleSystem[] = [];
  private playerAura: BABYLON.ParticleSystem | null = null;
  private projectileCounter: number = 0;
  private glowLayer: BABYLON.GlowLayer | null = null;

  constructor(private scene: BABYLON.Scene) {}

  /**
   * Crear un proyectil de KI
   */
  createProjectile(
    startPos: BABYLON.Vector3,
    targetPos: BABYLON.Vector3,
    damage: number,
    kiCost: number,
    speed: number = 50
  ): string {
    const projectileId = `projectile_${this.projectileCounter++}`;

    // Calcular dirección
    const direction = targetPos.subtract(startPos).normalize();
    const velocity = direction.scale(speed);

    // Crear datos del proyectil
    const projectile: Projectile = {
      id: projectileId,
      position: { x: startPos.x, y: startPos.y, z: startPos.z },
      velocity: { x: velocity.x, y: velocity.y, z: velocity.z },
      damage,
      kiCost,
      radius: 0.3,
      isActive: true,
    };

    this.projectiles.set(projectileId, projectile);

    // Crear mesh visual
    const mesh = this.createProjectileMesh(projectileId, startPos);
    this.projectileMeshes.set(projectileId, mesh);

    // Crear sistema de partículas
    this.createProjectileParticles(projectileId, mesh);

    return projectileId;
  }

  /**
   * Crear mesh del proyectil
   */
  private createProjectileMesh(id: string, position: BABYLON.Vector3): BABYLON.Mesh {
    // Crear esfera de KI
    const sphere = BABYLON.MeshBuilder.CreateSphere(
      `projectile_${id}`,
      { diameter: 0.6, segments: 16 },
      this.scene
    );

    sphere.position = position;

    // Material luminoso azul
    const material = new BABYLON.StandardMaterial(`projectile_mat_${id}`, this.scene);
    material.emissiveColor = new BABYLON.Color3(0, 0.8, 1);
    material.specularColor = new BABYLON.Color3(0.5, 0.5, 0.5);
    material.alpha = 0.9;

    // Usar Glow Layer compartido para efecto de brillo
    if (!this.glowLayer) {
      this.glowLayer = new BABYLON.GlowLayer('glow', this.scene);
      this.glowLayer.intensity = 1.5;
    }
    this.glowLayer.addIncludedOnlyMesh(sphere);

    sphere.material = material;

    return sphere;
  }

  /**
   * Crear sistema de partículas alrededor del proyectil
   */
  private createProjectileParticles(id: string, mesh: BABYLON.Mesh): void {
    const particleSystem = new BABYLON.ParticleSystem(
      `particles_${id}`,
      500,
      this.scene
    );

    particleSystem.emitter = mesh;
    particleSystem.minEmitBox = new BABYLON.Vector3(-0.3, -0.3, -0.3);
    particleSystem.maxEmitBox = new BABYLON.Vector3(0.3, 0.3, 0.3);

    // Velocidad de partículas
    particleSystem.minEmitPower = 0;
    particleSystem.maxEmitPower = 1;
    particleSystem.minLifeTime = 0.2;
    particleSystem.maxLifeTime = 0.5;

    // Color y tamaño
    particleSystem.minSize = 0.05;
    particleSystem.maxSize = 0.15;

    // Crear textura de partícula
    const particleTexture = new BABYLON.DynamicTexture('particleTexture', 64, this.scene);
    const ctx = particleTexture.getContext();
    ctx.fillStyle = 'white';
    ctx.beginPath();
    ctx.arc(32, 32, 32, 0, Math.PI * 2);
    ctx.fill();
    particleTexture.update();

    particleSystem.particleTexture = particleTexture;

    // Color de partículas (azul eléctrico)
    particleSystem.addColorGradient(0, new BABYLON.Color4(0, 0.8, 1, 1));
    particleSystem.addColorGradient(0.7, new BABYLON.Color4(0, 0.5, 1, 0.5));
    particleSystem.addColorGradient(1, new BABYLON.Color4(0, 0.3, 1, 0));

    particleSystem.start();
    this.particleSystems.push(particleSystem);
  }

  /**
   * Crear o actualizar el aura del jugador
   * @param emitter Mesh o cámara que emitirá el aura
   * @param npPercentage Porcentaje de NP (0-100)
   */
  updatePlayerAura(emitter: BABYLON.AbstractMesh | BABYLON.Camera, npPercentage: number): void {
    if (!this.playerAura) {
      this.playerAura = new BABYLON.ParticleSystem("playerAura", 1000, this.scene);
      
      // Textura de llamarada (gradiente radial)
      const auraType = new BABYLON.DynamicTexture("auraTex", 64, this.scene);
      const ctx = auraType.getContext();
      const grad = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
      grad.addColorStop(0, "rgba(255, 255, 255, 1)");
      grad.addColorStop(1, "rgba(255, 255, 255, 0)");
      ctx.fillStyle = grad;
      ctx.fillRect(0, 0, 64, 64);
      auraType.update();

      this.playerAura.particleTexture = auraType;
      this.playerAura.emitter = emitter as any;
      
      // Configuración base
      this.playerAura.minSize = 0.1;
      this.playerAura.maxSize = 0.5;
      this.playerAura.minLifeTime = 0.5;
      this.playerAura.maxLifeTime = 1.0;
      this.playerAura.emitRate = 200;
      this.playerAura.blendMode = BABYLON.ParticleSystem.BLENDMODE_ADD;
      
      // Gravedad negativa para que suba como fuego
      this.playerAura.gravity = new BABYLON.Vector3(0, 2, 0);
      
      this.playerAura.start();
    }

    // Escalar según NP
    const factor = npPercentage / 100;
    this.playerAura.minSize = 0.1 + factor * 0.5;
    this.playerAura.maxSize = 0.3 + factor * 1.0;
    this.playerAura.emitRate = 100 + factor * 900;
    
    // Cambiar color según umbrales
    if (npPercentage < 25) {
      this.playerAura.color1 = new BABYLON.Color4(1, 1, 1, 0.5); // Blanco tenue
    } else if (npPercentage < 50) {
      this.playerAura.color1 = new BABYLON.Color4(0, 0.6, 1, 0.8); // Azul
    } else if (npPercentage < 75) {
      this.playerAura.color1 = new BABYLON.Color4(1, 0.8, 0, 1.0); // Dorado
    } else {
      this.playerAura.color1 = new BABYLON.Color4(1, 1, 0.5, 1.0); // Eléctrico / Blanco
      this.playerAura.minSize *= 1.2; // Aumento final
    }
    
    this.playerAura.color2 = new BABYLON.Color4(this.playerAura.color1.r, this.playerAura.color1.g, this.playerAura.color1.b, 0);
  }

  /**
   * Actualizar posiciones de proyectiles
   */
  update(deltaTime: number): void {
    this.projectiles.forEach((projectile, id) => {
      if (!projectile.isActive) return;

      // Actualizar posición
      projectile.position.x += projectile.velocity.x * deltaTime;
      projectile.position.y += projectile.velocity.y * deltaTime;
      projectile.position.z += projectile.velocity.z * deltaTime;

      // Actualizar mesh
      const mesh = this.projectileMeshes.get(id);
      if (mesh) {
        mesh.position = new BABYLON.Vector3(
          projectile.position.x,
          projectile.position.y,
          projectile.position.z
        );
      }

      // Remover proyectiles que salieron del mapa
      if (Math.abs(projectile.position.z) > 100) {
        this.removeProjectile(id);
      }
    });
  }

  /**
   * Remover proyectil
   */
  removeProjectile(id: string): void {
    const projectile = this.projectiles.get(id);
    if (projectile) {
      projectile.isActive = false;
    }

    const mesh = this.projectileMeshes.get(id);
    if (mesh) {
      mesh.dispose();
      this.projectileMeshes.delete(id);
    }

    this.projectiles.delete(id);
  }

  /**
   * Obtener proyectiles activos
   */
  getActiveProjectiles(): Projectile[] {
    return Array.from(this.projectiles.values()).filter(p => p.isActive);
  }

  /**
   * Limpiar todos los efectos
   */
  dispose(): void {
    this.projectileMeshes.forEach(mesh => mesh.dispose());
    this.projectileMeshes.clear();
    this.projectiles.clear();
    this.particleSystems.forEach(ps => ps.dispose());
    this.particleSystems = [];
    if (this.glowLayer) {
      this.glowLayer.dispose();
      this.glowLayer = null;
    }
  }
}
