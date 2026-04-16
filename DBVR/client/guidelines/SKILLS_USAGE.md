# Guía de Uso de Skills - DBVR

Esta guía establece los estándares para trabajar con las "Skills" de IA y los sistemas de Machine Learning en el proyecto Dragon Ball VR.

## 1. Gesture Skill System (GSS)
El GSS es el núcleo del reconocimiento de gestos basado en KNN (K-Nearest Neighbors).

### Dimensiones de Características
- **ESTÁNDAR UNIFICADO:** Todas las muestras de entrenamiento y vectores de inferencia DEBEN tener **46 dimensiones**.
  - 1 a 16: Datos base (Body-centric wrist positions, distances, velocities, relative height).
  - 17 a 46: Datos de puntas de dedos (Fingertip relative positions to wrist).
- **Consistencia:** Si un gesto no requiere seguimiento de dedos (ej. `wristOnly`), los últimos 30 campos deben rellenarse con `0.0`. Esto evita fallos de "Shape mismatch" en el clasificador KNN de TensorFlow.js.

### Extracción Body-Centric
Los gestos se calculan respecto al **Pecho** del avatar (aprox. 25cm debajo del headset), no respecto a coordenadas globales. Esto permite que los gestos funcionen independientemente de la posición o rotación del jugador en el mundo.

## 2. Skills Externas (Antigravity Skills)

### `gesture-skill-system`
Usa esta skill para:
- Definir nuevos ataques o fases (PREP/FIRE).
- Configurar árboles de decisión (FSM) de gestos.
- Ajustar umbrales de confianza (`thresholds`).

### `tfjs-knn-babylonxr`
Usa esta skill para:
- Optimizaciones de bajo nivel en TensorFlow.js (WebGL vs CPU).
- Manejo de memoria de Tensores (siempre usa `tf.tidy()` o `.dispose()`).
- Integración de nuevos clasificadores si se requiere seguimiento de cuerpo completo (BlazePose).

### `dragon-ball-game`
Usa esta skill para:
- Consultar datos canónicos (Poderes, Multiplicadores de NP, Colores de Aura).
- Asegurar que los efectos visuales (VFX) representen fielmente el material original.

## 3. Flujo de Trabajo para Nuevos Gestos
1. **Definición:** Agrega el nuevo estado en `CharacterConfigs.ts`.
2. **Entrenamiento:** Usa el panel de calibración en VR para capturar al menos 20-30 frames por fase.
3. **Sincronización:** El GSS sincronizará automáticamente el archivo `.json` con el servidor `dbvr-server`.
4. **Validación:** Verifica que el nuevo gesto no colisione con gestos existentes (ej. Distancia crítica entre manos o altura relativa).

---

### Notas de Rendimiento
- **Nunca** llames a `switchCharacter` o `init` dentro de un bucle de renderizado o frecuentemente en respuesta a cambios de estado de combate menores. El sistema incluye guardas para evitar recargas de red innecesarias.
- Si el reconocimiento de un ataque falla sistemáticamente, revisa los `normalizationStats`. Una sesión de entrenamiento corrupta puede sesgar los promedios Z-score de todo el personaje. Usa `fullReset()` si es necesario.
