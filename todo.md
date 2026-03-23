# VR KI Combat - TODO

## Infraestructura
- [x] Inicializar proyecto con Vite + TypeScript
- [x] Convertir a full-stack (Express + tRPC + DB)
- [x] Esquema de base de datos (users, player_stats, match_replays, player_configs)
- [x] Routers tRPC (auth, stats, replays, config)
- [x] Almacenamiento S3 para replays de partidas
- [x] Migraciones de base de datos aplicadas

## Motor de Juego (BabylonJS)
- [x] Escena 3D con BabylonJS
- [x] Camara en primera persona
- [x] Entorno (skybox, suelo)
- [x] Enemigo con aura de particulas
- [x] Sistema de proyectiles con particulas
- [x] Efectos de impacto
- [x] Sistema de camara lenta (bullet time)
- [x] Controles de teclado (A/S/R)

## Interfaz de Usuario
- [x] Pantalla de inicio
- [x] HUD con barras de KI y salud
- [x] Indicador de estado de combate
- [x] Botones de accion en HUD
- [x] Efecto visual de camara lenta (borde purpura)

## Sistema de Combate
- [x] Gestion de KI (consumo y regeneracion)
- [x] Ataque basico con proyectil
- [x] Bloqueo temporal
- [x] Recarga de KI
- [ ] Sistema de repulsion (deflectar proyectiles)
- [ ] IA del enemigo (ataques automaticos)
- [ ] Sistema de combos
- [ ] Deteccion de gestos con WebXR Hand Tracking
- [ ] Modo VR completo para Meta Quest

## Almacenamiento y Progresion
- [x] Estructura de base de datos para replays
- [x] Upload de replays a S3
- [ ] Pantalla de historial de partidas
- [ ] Pantalla de estadisticas del jugador
- [ ] Configuracion de controles guardada en DB

## Proximos pasos (post-MVP)
- [ ] Mas tipos de ataques (Kamehameha, Rei Gun, etc.)
- [ ] Multiples escenarios
- [ ] Sistema de sonido y musica
- [ ] Sistema de progresion y niveles
- [ ] Modo multijugador
