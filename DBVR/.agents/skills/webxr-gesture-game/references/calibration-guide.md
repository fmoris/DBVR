# Calibration Guide & JSON Schema

Este archivo detalla cómo calibrar gestos en BabylonJS y cómo usar un enfoque basado en datos (Data-Driven) mediante archivos JSON para definir gestos, grupos y umbrales.

---

## 1. Concepto de Calibración "Basada en Datos"

En lugar de codificar `if (dist < 0.025)`, el sistema lee un archivo de configuración. Esto permite:
- **Ajustes rápidos**: Cambia la sensibilidad sin recompilar.
- **Perfiles de usuario**: Carga configuraciones diferentes para manos grandes o pequeñas.
- **Portabilidad**: El mismo gesto funciona en diferentes proyectos compartiendo el JSON.

---

## 2. Esquema JSON de Gestos (`gestures.json`)

```json
{
  "metadata": {
    "version": "1.0.0",
    "unit": "meters",
    "device": "Meta Quest 3"
  },
  "gestures": {
    "pinch": {
      "type": "distance",
      "joints": ["thumb-tip", "index-finger-tip"],
      "threshold": 0.025,
      "debounceFrames": 3
    },
    "fist": {
      "type": "curl",
      "fingers": ["index", "middle", "ring", "pinky"],
      "threshold": 0.65,
      "debounceFrames": 5
    },
    "thumbs-up": {
      "type": "orientation",
      "referenceJoint": "wrist",
      "targetJoint": "thumb-tip",
      "minYOffset": 0.05,
      "isFistBase": true
    }
  },
  "groups": {
    "combat": ["fist", "open-palm", "pinch"],
    "menu": ["point", "pinch"]
  }
}
```

---

## 3. Workflow de Calibración en BabylonJS

Para obtener los valores reales de los gestos en el headset:

1. **Activar Debug UI**: Usa `AdvancedDynamicTexture` para mostrar valores en tiempo real.
2. **Capturar Poses**:
   - Mantén la pose deseada por 5 segundos.
   - Registra el valor `distancia` o `flexión` (0-1).
   - Repite 3 veces para obtener un promedio.
3. **Establecer Umbral**:
   - `Umbral = (Valor_Mínimo_Detectado + Valor_Máximo_No_Gesto) / 2`.
   - Agrega un 10% de margen de seguridad.

### Código de Captura en Render Loop:

```typescript
scene.registerBeforeRender(() => {
  const currentDist = Vector3.Distance(
    hand.getJointMesh(WebXRHandJoint.THUMB_TIP).absolutePosition,
    hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP).absolutePosition
  );
  
  if (isRecording) {
    recordings.push(currentDist);
    // Calcular promedio al finalizar
  }
});
```

---

## 4. Implementación del Loader JSON

```typescript
class GestureLoader {
  static async LoadConfig(url: string): Promise<GestureConfig> {
    const response = await fetch(url);
    return await response.json();
  }

  static ApplyToEmitter(emitter: GestureEmitter, config: GestureConfig) {
    // Configura los detectores dinámicamente basados en el JSON
    for (const [name, data] of Object.entries(config.gestures)) {
      emitter.registerGesture(name, data);
    }
  }
}
```

---

## 5. Recomendaciones de Rendimiento

- **No valides todos los grupos a la vez**: Activa el grupo `combat` solo durante la pelea.
- **Unit Scaling**: Asegúrate de que las unidades en el JSON coincidan con las de BabylonJS (metros por defecto).
- **Handedness**: Algunos gestos en el JSON pueden ser específicos para una mano (ej: `aim` solo en la derecha).
