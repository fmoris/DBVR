import { int, mysqlEnum, mysqlTable, text, timestamp, varchar, float, bigint } from "drizzle-orm/mysql-core";

export const users = mysqlTable("users", {
  id: int("id").autoincrement().primaryKey(),
  openId: varchar("openId", { length: 64 }).notNull().unique(),
  name: text("name"),
  email: varchar("email", { length: 320 }),
  loginMethod: varchar("loginMethod", { length: 64 }),
  role: mysqlEnum("role", ["user", "admin"]).default("user").notNull(),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
  updatedAt: timestamp("updatedAt").defaultNow().onUpdateNow().notNull(),
  lastSignedIn: timestamp("lastSignedIn").defaultNow().notNull(),
});

export type User = typeof users.$inferSelect;
export type InsertUser = typeof users.$inferInsert;

// Estadisticas del jugador
export const playerStats = mysqlTable("player_stats", {
  id: int("id").autoincrement().primaryKey(),
  userId: int("userId").notNull(),
  totalMatches: int("totalMatches").default(0).notNull(),
  wins: int("wins").default(0).notNull(),
  losses: int("losses").default(0).notNull(),
  totalKiUsed: float("totalKiUsed").default(0).notNull(),
  totalDamageDealt: float("totalDamageDealt").default(0).notNull(),
  totalDamageBlocked: float("totalDamageBlocked").default(0).notNull(),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
  updatedAt: timestamp("updatedAt").defaultNow().onUpdateNow().notNull(),
});

export type PlayerStats = typeof playerStats.$inferSelect;
export type InsertPlayerStats = typeof playerStats.$inferInsert;

// Replays y grabaciones de partidas
export const matchReplays = mysqlTable("match_replays", {
  id: int("id").autoincrement().primaryKey(),
  userId: int("userId").notNull(),
  fileName: varchar("fileName", { length: 255 }).notNull(),
  fileKey: varchar("fileKey", { length: 512 }).notNull(),
  fileUrl: text("fileUrl").notNull(),
  fileSizeBytes: bigint("fileSizeBytes", { mode: "number" }).default(0).notNull(),
  mimeType: varchar("mimeType", { length: 128 }).default("application/json").notNull(),
  durationSeconds: float("durationSeconds").default(0).notNull(),
  result: mysqlEnum("result", ["win", "loss", "draw"]).notNull(),
  playerKiRemaining: float("playerKiRemaining").default(0).notNull(),
  enemyKiRemaining: float("enemyKiRemaining").default(0).notNull(),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
});

export type MatchReplay = typeof matchReplays.$inferSelect;
export type InsertMatchReplay = typeof matchReplays.$inferInsert;

// Configuraciones del jugador (controles, sensibilidad, etc.)
export const playerConfigs = mysqlTable("player_configs", {
  id: int("id").autoincrement().primaryKey(),
  userId: int("userId").notNull().unique(),
  fileKey: varchar("fileKey", { length: 512 }),
  fileUrl: text("fileUrl"),
  gestureThreshold: float("gestureThreshold").default(0.15).notNull(),
  slowMotionFactor: float("slowMotionFactor").default(0.3).notNull(),
  kiRegenRate: float("kiRegenRate").default(5.0).notNull(),
  hapticFeedback: mysqlEnum("hapticFeedback", ["off", "light", "strong"]).default("light").notNull(),
  updatedAt: timestamp("updatedAt").defaultNow().onUpdateNow().notNull(),
});

export type PlayerConfig = typeof playerConfigs.$inferSelect;
export type InsertPlayerConfig = typeof playerConfigs.$inferInsert;
