import { z } from 'zod';
import { distanceM, type LatLng } from '../lib/geo.js';

/** Signed location payload sent with every location-bearing request (spec F-04). */
export const LocationPayload = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  accuracy: z.number().nonnegative(),
  speed: z.number().optional(),
  timestamp: z.iso.datetime({ offset: true }),
  /** App Attest (iOS) / Play Integrity (Android) assertion. Enforced from F-17. */
  assertion: z.string().optional(),
});
export type LocationPayload = z.infer<typeof LocationPayload>;

export const MAX_FIX_AGE_MS = 30_000;
export const MAX_TRAVEL_KMH = 300;

export type FixProblem = 'stale' | 'suspicious';

export function checkFreshness(p: LocationPayload, now = Date.now()): FixProblem | null {
  const age = now - Date.parse(p.timestamp);
  // Allow a little clock skew into the future, but nothing older than 30 s.
  if (age > MAX_FIX_AGE_MS || age < -MAX_FIX_AGE_MS) return 'stale';
  return null;
}

export interface PreviousFix extends LatLng {
  at: Date;
}

/** True when getting from the previous fix to this one would need > 300 km/h. */
export function isImpossibleTravel(prev: PreviousFix | null, p: LocationPayload): boolean {
  if (!prev) return false;
  const meters = distanceM(prev, p);
  if (meters < 1_000) return false; // GPS jitter and small hops are never suspicious
  const seconds = Math.max(1, (Date.parse(p.timestamp) - prev.at.getTime()) / 1000);
  return (meters / seconds) * 3.6 > MAX_TRAVEL_KMH;
}
