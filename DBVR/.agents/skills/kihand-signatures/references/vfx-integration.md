# VFX Integration — Efectos de Energía Ki

## Colores canónicos por ataque

| Gesto | Color primario | Color secundario |
|---|---|---|
| Kamehameha | Azul `#3399FF` | Blanco eléctrico `#CCFFFF` |
| Ki-Blast | Amarillo dorado `#FFCC00` | Naranja `#FF8800` |
| Galick | Morado `#9900FF` | Rosa `#FF00AA` |
| Genkidama | Blanco puro `#FFFFFF` | Celeste `#AAEEFF` |

## Partículas de carga sobre la mano

```typescript
import { ParticleSystem } from '@babylonjs/core/Particles/particleSystem.js';
import { Texture } from '@babylonjs/core/Materials/Textures/texture.js';
import { Color4 } from '@babylonjs/core/Maths/math.color.js';
import { Vector3 } from '@babylonjs/core/Maths/math.vector.js';

function createKiChargeParticles(
  scene: Scene,
  emitterPosition: Vector3,
  color: Color4,
  intensity: number, // 0-1
): ParticleSystem {
  const ps = new ParticleSystem('kiCharge', Math.floor(100 * intensity), scene);
  ps.particleTexture = new Texture('textures/flare.png', scene);
  ps.emitter = emitterPosition;

  // Tamaño inversamente proporcional a la intensidad para efecto denso al cargarse
  ps.minSize = 0.01 + intensity * 0.03;
  ps.maxSize = 0.02 + intensity * 0.05;

  ps.color1 = color;
  ps.color2 = new Color4(1, 1, 1, 0.5);
  ps.colorDead = new Color4(color.r, color.g, color.b, 0);

  ps.minLifeTime = 0.08;
  ps.maxLifeTime = 0.25;
  ps.emitRate = 120 * intensity;

  // Emisión en esfera pequeña alrededor de la mano
  ps.createSphereEmitter(0.04);

  ps.minEmitPower = 0.05;
  ps.maxEmitPower = 0.2 * intensity;
  ps.updateSpeed = 0.02;
  ps.gravity = new Vector3(0, 0.1, 0); // sube levemente

  return ps;
}
```

## Proyectil de energía (Ki-Ball)

```typescript
import { MeshBuilder } from '@babylonjs/core/Meshes/meshBuilder.js';
import { PBRMaterial } from '@babylonjs/core/Materials/PBR/pbrMaterial.js';
import { Color3 } from '@babylonjs/core/Maths/math.color.js';
import { GlowLayer } from '@babylonjs/core/Layers/glowLayer.js';

function spawnKiBall(scene: Scene, origin: Vector3, direction: Vector3, color: Color3) {
  const ball = MeshBuilder.CreateSphere('kiBall', { diameter: 0.08, segments: 8 }, scene);
  ball.position.copyFrom(origin);

  const mat = new PBRMaterial('kiMat', scene);
  mat.emissiveColor = color;
  mat.albedoColor = Color3.Black();
  mat.metallic = 0;
  mat.roughness = 1;
  ball.material = mat;

  // Glow layer (una sola por escena, reutilizar si ya existe)
  let glow = scene.getGlowLayerByName('kiGlow') as GlowLayer;
  if (!glow) {
    glow = new GlowLayer('kiGlow', scene);
    glow.intensity = 0.8;
  }
  glow.addIncludedOnlyMesh(ball);

  // Movimiento simple: actualizar posición en onBeforeRender
  const speed = 15; // m/s
  const obs = scene.onBeforeRenderObservable.add(() => {
    const dt = scene.getEngine().getDeltaTime() / 1000;
    ball.position.addInPlace(direction.scale(speed * dt));
    // Auto-destruir después de 3 segundos o impacto
    if (Vector3.Distance(ball.position, origin) > 30) {
      scene.onBeforeRenderObservable.remove(obs);
      ball.dispose();
    }
  });

  return ball;
}
```

## Haz de Kamehameha (beam sostenido)

```typescript
import { Mesh } from '@babylonjs/core/Meshes/mesh.js';
import { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial.js';
import { Color3 } from '@babylonjs/core/Maths/math.color.js';

function spawnKamehamehaBeam(
  scene: Scene,
  origin: Vector3,
  direction: Vector3,
  chargeLevel: number,
): Mesh {
  const length = 5 + chargeLevel * 10;
  const radius = 0.05 + chargeLevel * 0.15;

  const beam = MeshBuilder.CreateCylinder('kameBeam', {
    height: length,
    diameter: radius * 2,
    tessellation: 12,
  }, scene);

  // Orientar el cilindro hacia la dirección del ataque
  beam.lookAt(origin.add(direction));
  beam.position.copyFrom(origin.add(direction.scale(length / 2)));

  const mat = new StandardMaterial('kameMat', scene);
  mat.emissiveColor = new Color3(0.3, 0.6, 1.0);
  mat.wireframe = false;
  mat.alpha = 0.85;
  beam.material = mat;

  // Auto-destruir después de 1.5 segundos
  setTimeout(() => beam.dispose(), 1500);
  return beam;
}
```

## Optimización para Quest (Mobile GPU)

- Usa máximo **1 GlowLayer** por escena — compartir entre todos los ataques.
- Limita `ParticleSystem` a **100 partículas** por sistema en Quest 2, **200** en Quest 3.
- Usa `StandardMaterial` con `emissiveColor` en lugar de `PBRMaterial` cuando no sea necesario.
- Destruye los projectiles tras impacto o timeout para evitar acumulación de meshes.
- Para efectos de trail, usa `TrailMesh` en lugar de partículas cuando sea posible.
