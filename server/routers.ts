import { z } from "zod";
import { COOKIE_NAME } from "@shared/const";
import { getSessionCookieOptions } from "./_core/cookies";
import { systemRouter } from "./_core/systemRouter";
import { protectedProcedure, publicProcedure, router } from "./_core/trpc";
import { storagePut, storageGet } from "./storage";
import {
  getOrCreatePlayerStats,
  updatePlayerStats,
  saveMatchReplay,
  getUserReplays,
  deleteReplay,
  getPlayerConfig,
  upsertPlayerConfig,
} from "./db";
import { nanoid } from "nanoid";

export const appRouter = router({
  system: systemRouter,

  auth: router({
    me: publicProcedure.query((opts) => opts.ctx.user),
    logout: publicProcedure.mutation(({ ctx }) => {
      const cookieOptions = getSessionCookieOptions(ctx.req);
      ctx.res.clearCookie(COOKIE_NAME, { ...cookieOptions, maxAge: -1 });
      return { success: true } as const;
    }),
  }),

  // Estadisticas del jugador
  stats: router({
    get: protectedProcedure.query(async ({ ctx }) => {
      return getOrCreatePlayerStats(ctx.user.id);
    }),

    recordMatch: protectedProcedure
      .input(
        z.object({
          result: z.enum(["win", "loss", "draw"]),
          kiUsed: z.number().min(0),
          damageDealt: z.number().min(0),
          damageBlocked: z.number().min(0),
        })
      )
      .mutation(async ({ ctx, input }) => {
        const current = await getOrCreatePlayerStats(ctx.user.id);
        if (!current) return null;
        await updatePlayerStats(ctx.user.id, {
          totalMatches: current.totalMatches + 1,
          wins: input.result === "win" ? current.wins + 1 : current.wins,
          losses: input.result === "loss" ? current.losses + 1 : current.losses,
          totalKiUsed: current.totalKiUsed + input.kiUsed,
          totalDamageDealt: current.totalDamageDealt + input.damageDealt,
          totalDamageBlocked: current.totalDamageBlocked + input.damageBlocked,
        });
        return getOrCreatePlayerStats(ctx.user.id);
      }),
  }),

  // Replays y almacenamiento de archivos
  replays: router({
    list: protectedProcedure.query(async ({ ctx }) => {
      return getUserReplays(ctx.user.id);
    }),

    upload: protectedProcedure
      .input(
        z.object({
          fileName: z.string().max(255),
          content: z.string(),
          mimeType: z.string().default("application/json"),
          durationSeconds: z.number().min(0).default(0),
          result: z.enum(["win", "loss", "draw"]),
          playerKiRemaining: z.number().min(0).max(100).default(0),
          enemyKiRemaining: z.number().min(0).max(100).default(0),
        })
      )
      .mutation(async ({ ctx, input }) => {
        const suffix = nanoid(8);
        const fileKey = `replays/${ctx.user.id}/${suffix}-${input.fileName}`;
        const buffer = Buffer.from(input.content, "utf-8");
        const { url } = await storagePut(fileKey, buffer, "application/json");
        await saveMatchReplay({
          userId: ctx.user.id,
          fileName: input.fileName,
          fileKey,
          fileUrl: url,
          fileSizeBytes: buffer.byteLength,
          mimeType: input.mimeType,
          durationSeconds: input.durationSeconds,
          result: input.result,
          playerKiRemaining: input.playerKiRemaining,
          enemyKiRemaining: input.enemyKiRemaining,
        });
        return { url, fileKey };
      }),

    getDownloadUrl: protectedProcedure
      .input(z.object({ fileKey: z.string() }))
      .query(async ({ input }) => {
        const { url } = await storageGet(input.fileKey, 3600);
        return { url };
      }),

    delete: protectedProcedure
      .input(z.object({ replayId: z.number() }))
      .mutation(async ({ ctx, input }) => {
        await deleteReplay(input.replayId);
        return { success: true };
      }),
  }),

  // Configuracion del jugador
  config: router({
    get: protectedProcedure.query(async ({ ctx }) => {
      const config = await getPlayerConfig(ctx.user.id);
      return (
        config ?? {
          gestureThreshold: 0.15,
          slowMotionFactor: 0.3,
          kiRegenRate: 5.0,
          hapticFeedback: "light" as const,
          fileKey: null,
          fileUrl: null,
        }
      );
    }),

    update: protectedProcedure
      .input(
        z.object({
          gestureThreshold: z.number().min(0.05).max(0.5).optional(),
          slowMotionFactor: z.number().min(0.1).max(0.9).optional(),
          kiRegenRate: z.number().min(1).max(20).optional(),
          hapticFeedback: z.enum(["off", "light", "strong"]).optional(),
        })
      )
      .mutation(async ({ ctx, input }) => {
        await upsertPlayerConfig(ctx.user.id, input);
        return getPlayerConfig(ctx.user.id);
      }),
  }),
});

export type AppRouter = typeof appRouter;
