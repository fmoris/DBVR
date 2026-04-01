# VR KI Combat - Instalación Local

## Requisitos previos
- Node.js 18+ (https://nodejs.org)
- pnpm: `npm install -g pnpm`

## Pasos de instalación

### 1. Extraer el proyecto
Descomprime `vr_ki_combat.tar.gz` en esta carpeta.
En Windows puedes usar 7-Zip o el explorador de archivos.

O desde PowerShell/Git Bash:
```bash
tar -xzf vr_ki_combat.tar.gz
cd vr_ki_combat
```

### 2. Instalar dependencias
```bash
pnpm install
```

### 3. Configurar variables de entorno
Crea un archivo `.env` en la raíz del proyecto con:
```
# Requerido para el servidor
JWT_SECRET=una_clave_secreta_local
NODE_ENV=development

# Opcional: base de datos MySQL local
# DATABASE_URL=mysql://user:pass@localhost:3306/vr_ki_combat
```

> **Nota:** Sin `DATABASE_URL`, el juego funciona igual pero sin persistencia de datos (stats, replays).

### 4. Iniciar el servidor de desarrollo
```bash
pnpm dev
```

Abre https://localhost:3000 en tu navegador. (Acepta la advertencia de seguridad).

### 5. Probar el juego
- Presiona **"Iniciar Combate"**
- **A** = Lanzar ataque de KI
- **S** = Activar bloqueo
- **R** = Recargar energía KI

---

## Para Meta Quest (VR)
1. Asegúrate de que tu PC y el Quest estén en la misma red WiFi
2. En el Quest, abre Oculus Browser
3. Navega a `https://[IP-de-tu-PC]:3000`
4. Al ver "La conexión no es privada", ve a Configuración Avanzada y selecciona Continuar.
5. Haz click en el botón VR para entrar en modo inmersivo

---

## Estructura del proyecto
```
vr_ki_combat/
├── client/src/
│   ├── game/
│   │   ├── BabylonScene.ts    ← Motor del juego
│   │   ├── GameCanvas.tsx     ← Componente React del canvas
│   │   └── GameHUD.tsx        ← HUD con barras de KI
│   └── pages/Home.tsx         ← Pantalla principal
├── server/
│   ├── routers.ts             ← API tRPC (stats, replays, config)
│   ├── db.ts                  ← Queries de base de datos
│   └── storage.ts             ← Almacenamiento S3
├── drizzle/schema.ts          ← Esquema de base de datos
└── todo.md                    ← Lista de features pendientes
```
