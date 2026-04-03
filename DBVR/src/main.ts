/**
 * VR KI Combat - Aplicación Principal
 * Juego de combate VR en primera persona con detección de movimientos de brazos
 */

import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';
import { CombatStateManager } from './systems/CombatStateManager';
import { GestureRecognizer } from './systems/GestureRecognizer';
import { PlayerStats } from './systems/PlayerStats';
import { VFXManager } from './systems/VFXManager';
import { WebXRManager } from './systems/WebXRManager';
import { CombatState, GestureType } from './types';

class VRKICombatGame {
  private engine: BABYLON.Engine;
  private scene: BABYLON.Scene;
  private camera: BABYLON.UniversalCamera;

  // Sistemas del juego
  private combatStateManager: CombatStateManager;
  private gestureRecognizer: GestureRecognizer;
  private playerStats: PlayerStats;
  private vfxManager: VFXManager;
  private webxrManager: WebXRManager;

  // Enemigo simulado
  private enemyPosition: BABYLON.Vector3 = new BABYLON.Vector3(0, 1.5, 20);
  private enemyMesh: BABYLON.Mesh | null = null;

  // Control de ataque
  private isCharging: boolean = false;
  private chargeStartTime: number = 0;
  private lastAttackTime: number = 0;
  private attackCooldown: number = 0.5; // segundos

  constructor() {
    // Obtener canvas
    const canvas = document.getElementById('canvas') as unknown as HTMLCanvasElement;

    // Crear engine
    this.engine = new BABYLON.Engine(canvas, true, {
      preserveDrawingBuffer: true,
      antialias: true,
    });

    // Crear escena
    this.scene = new BABYLON.Scene(this.engine);
    this.scene.collisionsEnabled = true;
    this.scene.gravity = new BABYLON.Vector3(0, 0, 0); // Sin gravedad en VR

    // Crear cámara
    this.camera = new BABYLON.UniversalCamera('camera', new BABYLON.Vector3(0, 1.6, 0));
    this.camera.attachControl(canvas, true);
    this.camera.speed = 0;
    this.camera.inertia = 0.7;
    this.camera.angularSensibility = 1000;

    // Inicializar sistemas
    this.combatStateManager = new CombatStateManager(this.scene);
    this.gestureRecognizer = new GestureRecognizer();
    this.playerStats = new PlayerStats();
    this.vfxManager = new VFXManager(this.scene);
    this.webxrManager = new WebXRManager(this.scene);

    this.setupScene();
    this.setupEventListeners();
  }

  /**
   * Configurar la escena
   */
  private setupScene(): void {
    // Luz ambiental
    const ambientLight = new BABYLON.HemisphericLight(
      'ambientLight',
      new BABYLON.Vector3(0, 1, 0),
      this.scene
    );
    ambientLight.intensity = 0.6;

    // Luz direccional (sol)
    const sunLight = new BABYLON.PointLight('sunLight', new BABYLON.Vector3(10, 20, 10), this.scene);
    sunLight.intensity = 0.8;
    sunLight.range = 100;

    // Cielo
    this.createSkybox();

    // Terreno
    this.createGround();

    // Enemigo
    this.createEnemy();

    // Volumen de colisión para detección de impactos
    this.createCollisionVolumes();
  }

  /**
   * Crear skybox
   */
  private createSkybox(): void {
    const skybox = BABYLON.MeshBuilder.CreateBox('skybox', { size: 1000 }, this.scene);
    const skyboxMaterial = new BABYLON.StandardMaterial('skyboxMaterial', this.scene);
    (skyboxMaterial as any).emissiveColor = new BABYLON.Color3(0.2, 0.3, 0.5);
    skybox.material = skyboxMaterial;
  }

  /**
   * Crear terreno
   */
  private createGround(): void {
    const ground = BABYLON.MeshBuilder.CreateGround(
      'ground',
      { width: 100, height: 100 },
      this.scene
    );

    const groundMaterial = new BABYLON.StandardMaterial('groundMaterial', this.scene);
    (groundMaterial as any).diffuse = new BABYLON.Color3(0.3, 0.3, 0.3);
    (groundMaterial as any).specularColor = new BABYLON.Color3(0.2, 0.2, 0.2);
    ground.material = groundMaterial;
    ground.position.y = -2;
  }

  /**
   * Crear enemigo
   */
  private createEnemy(): void {
    this.enemyMesh = BABYLON.MeshBuilder.CreateCylinder(
      'enemy',
      { height: 2, diameterTop: 0.6, diameterBottom: 0.6 },
      this.scene
    );

    this.enemyMesh.position = this.enemyPosition;

    const enemyMaterial = new BABYLON.StandardMaterial('enemyMaterial', this.scene);
    (enemyMaterial as any).diffuse = new BABYLON.Color3(0.8, 0.2, 0.2);
    (enemyMaterial as any).emissiveColor = new BABYLON.Color3(0.2, 0, 0);
    this.enemyMesh.material = enemyMaterial;
  }

  /**
   * Crear volúmenes de colisión
   */
  private createCollisionVolumes(): void {
    // Volumen de colisión del enemigo
    if (this.enemyMesh) {
      this.enemyMesh.checkCollisions = true;
    }
  }

  /**
   * Configurar event listeners
   */
  private setupEventListeners(): void {
    // Botón para entrar en VR
    document.addEventListener('click', () => {
      this.webxrManager.enterVR().catch(console.error);
    });

    // Teclas para testing (cuando no está en VR)
    document.addEventListener('keydown', (e) => {
      switch (e.key.toLowerCase()) {
        case 'a':
          this.simulateAttack();
          break;
        case 's':
          this.simulateBlock();
          break;
        case 'r':
          this.simulateRecharge();
          break;
      }
    });
  }

  /**
   * Inicializar el juego
   */
  async initialize(): Promise<void> {
    console.log('🎮 Inicializando VR KI Combat...');

    // Inicializar WebXR
    const xrAvailable = await this.webxrManager.initializeWebXR();
    if (!xrAvailable) {
      console.warn('⚠️ WebXR no disponible. Usando modo fallback.');
    }

    // Iniciar loop de renderizado
    this.startGameLoop();

    console.log('✅ Juego inicializado');
  }

  /**
   * Loop principal del juego
   */
  private startGameLoop(): void {
    this.engine.runRenderLoop(() => {
      const deltaTime = this.engine.getDeltaTime() / 1000; // Convertir a segundos

      // Actualizar sistemas
      this.update(deltaTime);

      // Renderizar
      this.scene.render();
    });

    // Manejar redimensionamiento
    window.addEventListener('resize', () => {
      this.engine.resize();
    });
  }

  /**
   * Actualizar lógica del juego
   */
  private update(deltaTime: number): void {
    // Actualizar WebXR
    this.webxrManager.updateHandTracking();

    // Actualizar sistemas
    this.combatStateManager.update(deltaTime);
    this.playerStats.update();
    this.vfxManager.update(deltaTime);
    this.vfxManager.updatePlayerAura(this.camera, this.playerStats.getNPPercentage());

    // Actualizar gestos
    const leftHands = this.webxrManager.getLeftHandJoints();
    const rightHands = this.webxrManager.getRightHandJoints();

    if (leftHands) {
      this.gestureRecognizer.updateHandJoints('left', leftHands);
    }
    if (rightHands) {
      this.gestureRecognizer.updateHandJoints('right', rightHands);
    }

    // Procesar gesto actual
    this.processGesture(deltaTime);

    // Detectar colisiones de proyectiles
    this.checkProjectileCollisions();

    // Actualizar UI
    this.updateUI();

    // Debug info
    this.updateDebugInfo();
  }

  /**
   * Procesar gesto actual
   */
  private processGesture(deltaTime: number): void {
    const gesture = this.gestureRecognizer.getCurrentGesture();

    switch (gesture) {
      case GestureType.CHARGING:
        this.handleCharging(deltaTime);
        break;
      case GestureType.ATTACKING:
        this.handleAttacking();
        break;
      case GestureType.BLOCKING:
        this.handleBlocking();
        break;
      case GestureType.RECHARGING:
        this.handleRecharging(deltaTime);
        break;
    }
  }

  /**
   * Manejar carga de ataque
   */
  private handleCharging(_deltaTime: number): void {
    if (!this.isCharging) {
      this.isCharging = true;
      this.chargeStartTime = Date.now();
      console.log('⚡ Iniciando carga de ataque');
    }
  }

  /**
   * Manejar ataque
   */
  private handleAttacking(): void {
    if (!this.isCharging) return;

    const now = Date.now();
    if (now - this.lastAttackTime < this.attackCooldown * 1000) return;

    const chargeTime = (now - this.chargeStartTime) / 1000;
    this.isCharging = false;
    this.lastAttackTime = now;

    // Determinar tipo de ataque basado en tiempo de carga
    let attackType: 'basic' | 'charged' = 'basic';
    let kiCost = 10;
    let damage = 15;

    if (chargeTime > 2) {
      attackType = 'charged';
      kiCost = 30;
      damage = 50;
    }

    // Consumir KI
    if (!this.playerStats.consumeKi(kiCost)) {
      console.log('❌ KI insuficiente');
      return;
    }

    // Crear proyectil
    const startPos = new BABYLON.Vector3(0, 1.2, 0);
    this.vfxManager.createProjectile(
      startPos,
      this.enemyPosition,
      damage,
      kiCost,
      50
    );

    console.log(`🔥 ${attackType === 'charged' ? 'Ataque Cargado' : 'Ataque Básico'} lanzado`);

    // Iniciar cámara lenta
    this.combatStateManager.startSlowMotion(1.5, 0.3);
  }

  /**
   * Manejar bloqueo
   */
  private handleBlocking(): void {
    if (this.combatStateManager.getState() !== CombatState.DEFENDING) {
      this.combatStateManager.transitionTo(CombatState.DEFENDING);
      console.log('🛡️ Bloqueando');
    }
  }

  /**
   * Manejar recarga de KI
   */
  private handleRecharging(_deltaTime: number): void {
    // La recarga ya se maneja en PlayerStats.update()
  }

  /**
   * Verificar colisiones de proyectiles
   */
  private checkProjectileCollisions(): void {
    if (!this.enemyMesh) return;

    const projectiles = this.vfxManager.getActiveProjectiles();
    const minPoint = this.enemyMesh.getAbsolutePosition().subtract(new BABYLON.Vector3(0.3, 1, 0.3));
    const maxPoint = this.enemyMesh.getAbsolutePosition().add(new BABYLON.Vector3(0.3, 1, 0.3));
    const enemyBounds = new BABYLON.BoundingInfo(minPoint, maxPoint);

    projectiles.forEach((projectile) => {
      const projectilePos = new BABYLON.Vector3(
        projectile.position.x,
        projectile.position.y,
        projectile.position.z
      );

      if (enemyBounds.intersectsPoint(projectilePos)) {
        console.log(`💥 ¡Impacto! Daño: ${projectile.damage}`);
        this.vfxManager.removeProjectile(projectile.id);
        this.createImpactEffect(projectilePos);
      }
    });
  }

  /**
   * Crear efecto de impacto
   */
  private createImpactEffect(position: BABYLON.Vector3): void {
    const impact = BABYLON.MeshBuilder.CreateSphere('impact', { diameter: 1 }, this.scene);
    impact.position = position;

    const impactMaterial = new BABYLON.StandardMaterial('impactMat', this.scene);
    impactMaterial.emissiveColor = new BABYLON.Color3(1, 1, 0);
    impact.material = impactMaterial;

    // Animar desaparición
    let alpha = 1;
    const animationInterval = setInterval(() => {
      alpha -= 0.1;
      impactMaterial.alpha = alpha;

      if (alpha <= 0) {
        clearInterval(animationInterval);
        impact.dispose();
      }
    }, 50);
  }

  /**
   * Actualizar UI
   */
  private updateUI(): void {
    const playerKiBar = document.getElementById('playerKiBar') as HTMLElement;
    const playerAuraIcon = document.getElementById('playerAuraIcon') as HTMLElement; // Nuevo elemento para brillo

    if (playerKiBar) {
      playerKiBar.style.width = `${this.playerStats.getKiPercentage()}%`;
    }

    // El NP no se muestra en barra, se "siente" (puedes añadir un brillo al HUD)
    if (playerAuraIcon) {
      const npFactor = this.playerStats.getNPPercentage() / 100;
      playerAuraIcon.style.opacity = `${0.3 + npFactor * 0.7}`;
      playerAuraIcon.style.filter = `blur(${npFactor * 10}px) brightness(${1 + npFactor})`;
    }
  }

  /**
   * Actualizar información de debug
   */
  private updateDebugInfo(): void {
    const debugInfo = document.getElementById('debugInfo') as HTMLElement;
    if (!debugInfo) return;

    const gesture = this.gestureRecognizer.getCurrentGesture();
    const state = this.combatStateManager.getState();
    const stats = this.playerStats.getStats();

    debugInfo.innerHTML = `
      <div><strong>Estado Combate:</strong> ${state}</div>
      <div><strong>Gesto:</strong> ${gesture}</div>
      <div><strong>KI:</strong> ${stats.ki.toFixed(1)}/${stats.maxKi}</div>
      <div><strong>NP (Oculto):</strong> ${stats.np.toFixed(0)} (Umbral: ${this.playerStats.getCurrentThreshold()})</div>
      <div><strong>Cámara Lenta:</strong> ${this.combatStateManager.isInSlowMotion() ? 'SÍ' : 'NO'}</div>
      <div><strong>WebXR:</strong> ${this.webxrManager.isHandTrackingAvailable() ? 'Activo' : 'Inactivo'}</div>
      <div style="margin-top: 10px; font-size: 10px; color: #00aa00;">
        Controles: A=Ataque | S=Bloqueo | R=Recarga
      </div>
    `;
  }

  /**
   * Simuladores para testing (sin VR)
   */
  private simulateAttack(): void {
    console.log('🔥 Simulando ataque');
    this.isCharging = true;
    this.chargeStartTime = Date.now() - 2000; // Simular carga de 2 segundos
    this.handleAttacking();
  }

  private simulateBlock(): void {
    console.log('🛡️ Simulando bloqueo');
    this.combatStateManager.transitionTo(CombatState.DEFENDING);
  }

  private simulateRecharge(): void {
    console.log('⚡ Simulando recarga');
    this.playerStats.consumeKi(-20); // Agregar KI
  }
}

// Iniciar aplicación
const game = new VRKICombatGame();
game.initialize().catch(console.error);
