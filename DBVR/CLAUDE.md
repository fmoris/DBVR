# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VR KI Combat is a WebXR-based VR fighting game inspired by Yu Yu Hakusho. Features action-reaction combat system, KI energy management, hand gesture recognition, and particle-based VFX.

**Stack**: TypeScript, Vite, React, Express, tRPC, Drizzle ORM, BabylonJS, WebXR

## Common Commands

```bash
# Development (starts HTTPS server required for WebXR)
pnpm dev

# Build for production
pnpm build

# Type check
pnpm check

# Run tests (server-side only)
pnpm test

# Database migrations (requires DATABASE_URL in .env)
pnpm db:push
```

## Project Structure

```
client/          # React frontend + BabylonJS game engine
  src/game/      # Core game systems (Game.ts, CombatSystem.ts, VFXManager.ts, etc.)
  src/pages/     # React pages (Home.tsx is main entry)
  src/_core/     # tRPC client, auth utilities

server/          # Express + tRPC backend
  _core/         # Server setup, auth context, tRPC base
  routers.ts     # Main tRPC router (stats, replays, config)
  db.ts          # Drizzle ORM queries
  storage.ts     # S3-compatible storage for replays

shared/          # Shared types and constants
  _core/         # Error definitions

drizzle/         # Database schema and migrations
  schema.ts      # MySQL table definitions
```

## Architecture Patterns

### tRPC API Structure

Procedures are defined in `server/routers.ts` with three access levels:
- `publicProcedure` - No auth required
- `protectedProcedure` - Requires valid JWT session
- `adminProcedure` - Requires admin role

Client calls tRPC via React Query hooks in `client/src/lib/trpc.ts`.

### Authentication Flow

1. OAuth via external portal (configured via `VITE_OAUTH_PORTAL_URL`)
2. Callback handled at `server/_core/oauth.ts`
3. JWT stored in cookie (`app_session_id`)
4. SDK validates token in `server/_core/sdk.ts`

### Database

Drizzle ORM with MySQL. Connection is lazy - app works without DB for local dev, but stats/replays won't persist.

Key tables: `users`, `playerStats`, `matchReplays`, `playerConfigs`

### Game Architecture

Core game loop in `client/src/game/`:
- `Game.ts` - Main entry, initializes all systems
- `CombatSystem.ts` - State machine (neutral/charging/attacking/defending/slowMotion)
- `VFXManager.ts` - Particle systems and projectile effects
- `GestureRecognizer.ts` - WebXR hand tracking for gestures
- `WebXRManager.ts` - VR session management
- `BabylonScene.ts` - Legacy wrapper (being replaced by Game.ts)

### HTTPS Requirement

WebXR `immersive-vr` requires HTTPS. In development, `server/_core/index.ts` auto-generates self-signed certificates via `selfsigned` package. Users must accept the certificate warning.

## Testing

Vitest configured for server tests only (`server/**/*.test.ts`). No client-side test setup currently.

## Environment Variables

Required for basic dev:
```
JWT_SECRET=any_secret_for_local_dev
NODE_ENV=development
```

Optional (enables features):
```
DATABASE_URL=mysql://user:pass@localhost:3306/db
VITE_OAUTH_PORTAL_URL=https://...
VITE_APP_ID=your_app_id
BUILT_IN_FORGE_API_URL=https://...
BUILT_IN_FORGE_API_KEY=...
```

## Code Style

Prettier configured with 2-space tabs, semicolons, double quotes, 80 char width. No ESLint setup currently.

## Active Skills

### 🥽 metaquest-webxr (v1.0.0)

Skill activado para guía experta en desarrollo WebXR para Meta Quest. Consultar para:
- Configuración de hand tracking y gestos
- Optimización de rendimiento para Quest (Adreno GPU)
- Patrones de interacción VR (grabbing, teleportation)
- Debug de WebXR y HTTPS
- Arquitectura de escenas Babylon.js

Ubicación: `.clawhub/metaquest-webxr/`
Referencias:
- `hand-tracking.md` — 26 joints, gestos, grab detection
- `webxr-features.md` — XR session, features disponibles
- `performance.md` — Límites GPU, draw calls, texturas
- `deployment.md` — HTTPS, Quest browser, testing
