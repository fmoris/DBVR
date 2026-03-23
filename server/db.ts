import { eq } from "drizzle-orm";
import { drizzle } from "drizzle-orm/mysql2";
import {
  InsertUser,
  InsertMatchReplay,
  InsertPlayerConfig,
  InsertPlayerStats,
  matchReplays,
  playerConfigs,
  playerStats,
  users,
} from "../drizzle/schema";
import { ENV } from './_core/env';

let _db: ReturnType<typeof drizzle> | null = null;

// Lazily create the drizzle instance so local tooling can run without a DB.
export async function getDb() {
  if (!_db && process.env.DATABASE_URL) {
    try {
      _db = drizzle(process.env.DATABASE_URL);
    } catch (error) {
      console.warn("[Database] Failed to connect:", error);
      _db = null;
    }
  }
  return _db;
}

export async function upsertUser(user: InsertUser): Promise<void> {
  if (!user.openId) {
    throw new Error("User openId is required for upsert");
  }

  const db = await getDb();
  if (!db) {
    console.warn("[Database] Cannot upsert user: database not available");
    return;
  }

  try {
    const values: InsertUser = {
      openId: user.openId,
    };
    const updateSet: Record<string, unknown> = {};

    const textFields = ["name", "email", "loginMethod"] as const;
    type TextField = (typeof textFields)[number];

    const assignNullable = (field: TextField) => {
      const value = user[field];
      if (value === undefined) return;
      const normalized = value ?? null;
      values[field] = normalized;
      updateSet[field] = normalized;
    };

    textFields.forEach(assignNullable);

    if (user.lastSignedIn !== undefined) {
      values.lastSignedIn = user.lastSignedIn;
      updateSet.lastSignedIn = user.lastSignedIn;
    }
    if (user.role !== undefined) {
      values.role = user.role;
      updateSet.role = user.role;
    } else if (user.openId === ENV.ownerOpenId) {
      values.role = 'admin';
      updateSet.role = 'admin';
    }

    if (!values.lastSignedIn) {
      values.lastSignedIn = new Date();
    }

    if (Object.keys(updateSet).length === 0) {
      updateSet.lastSignedIn = new Date();
    }

    await db.insert(users).values(values).onDuplicateKeyUpdate({
      set: updateSet,
    });
  } catch (error) {
    console.error("[Database] Failed to upsert user:", error);
    throw error;
  }
}

export async function getUserByOpenId(openId: string) {
  const db = await getDb();
  if (!db) {
    console.warn("[Database] Cannot get user: database not available");
    return undefined;
  }

  const result = await db.select().from(users).where(eq(users.openId, openId)).limit(1);

  return result.length > 0 ? result[0] : undefined;
}

// ─── Estadisticas ─────────────────────────────────────────────────────────────

export async function getOrCreatePlayerStats(userId: number) {
  const db = await getDb();
  if (!db) return null;
  const existing = await db.select().from(playerStats).where(eq(playerStats.userId, userId)).limit(1);
  if (existing.length > 0) return existing[0];
  await db.insert(playerStats).values({ userId });
  const created = await db.select().from(playerStats).where(eq(playerStats.userId, userId)).limit(1);
  return created[0] ?? null;
}

export async function updatePlayerStats(userId: number, data: Partial<InsertPlayerStats>) {
  const db = await getDb();
  if (!db) return;
  await db.update(playerStats).set(data).where(eq(playerStats.userId, userId));
}

// ─── Replays ──────────────────────────────────────────────────────────────────

export async function saveMatchReplay(data: InsertMatchReplay) {
  const db = await getDb();
  if (!db) return null;
  await db.insert(matchReplays).values(data);
  const result = await db
    .select()
    .from(matchReplays)
    .where(eq(matchReplays.userId, data.userId))
    .orderBy(matchReplays.createdAt)
    .limit(1);
  return result[0] ?? null;
}

export async function getUserReplays(userId: number) {
  const db = await getDb();
  if (!db) return [];
  return db
    .select()
    .from(matchReplays)
    .where(eq(matchReplays.userId, userId))
    .orderBy(matchReplays.createdAt);
}

export async function deleteReplay(replayId: number) {
  const db = await getDb();
  if (!db) return;
  await db.delete(matchReplays).where(eq(matchReplays.id, replayId));
}

// ─── Configuracion ────────────────────────────────────────────────────────────

export async function getPlayerConfig(userId: number) {
  const db = await getDb();
  if (!db) return null;
  const result = await db.select().from(playerConfigs).where(eq(playerConfigs.userId, userId)).limit(1);
  return result[0] ?? null;
}

export async function upsertPlayerConfig(userId: number, data: Partial<InsertPlayerConfig>) {
  const db = await getDb();
  if (!db) return;
  const existing = await db.select().from(playerConfigs).where(eq(playerConfigs.userId, userId)).limit(1);
  if (existing.length > 0) {
    await db.update(playerConfigs).set(data).where(eq(playerConfigs.userId, userId));
  } else {
    await db.insert(playerConfigs).values({ userId, ...data });
  }
}
