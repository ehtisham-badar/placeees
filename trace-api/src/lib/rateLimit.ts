import { recordIntegrityEvent } from '../integrity/events.js';
import { AppError } from './errors.js';

/** Per-user limits for actions that touch location or create content (spec F-17). */
export const ACTION_LIMITS = {
  unlock: { max: 30, windowMs: 60_000 },
  nearHint: { max: 30, windowMs: 60_000 },
  createDrop: { max: 6, windowMs: 60_000 },
  dropCheck: { max: 20, windowMs: 60_000 },
  echo: { max: 10, windowMs: 60_000 },
  nowPhoto: { max: 6, windowMs: 60_000 },
  relay: { max: 10, windowMs: 60_000 },
  report: { max: 20, windowMs: 3_600_000 },
} as const;
export type Action = keyof typeof ACTION_LIMITS;

// In-memory sliding windows. One API instance is enough for the pilot; move to Redis when scaling out.
const windows = new Map<string, number[]>();

/** Records a hit and returns whether it's within the limit. */
export function hit(key: string, max: number, windowMs: number, now = Date.now()): boolean {
  const recent = (windows.get(key) ?? []).filter((t) => now - t < windowMs);
  const allowed = recent.length < max;
  if (allowed) recent.push(now);
  windows.set(key, recent);
  return allowed;
}

export async function limitAction(userId: string, action: Action) {
  const { max, windowMs } = ACTION_LIMITS[action];
  if (hit(`${action}:${userId}`, max, windowMs)) return;
  await recordIntegrityEvent(userId, 'rate_limited', { action });
  throw new AppError('rate_limited', 429);
}

// Drop empty windows now and then so the map can't grow without bound.
setInterval(() => {
  const now = Date.now();
  for (const [key, times] of windows) {
    if (times.every((t) => now - t > 3_600_000)) windows.delete(key);
  }
}, 600_000).unref();
