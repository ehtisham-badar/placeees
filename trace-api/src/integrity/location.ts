import { z } from 'zod';
import { distanceM, type LatLng } from '../lib/geo.js';

/** Signed location payload sent with every location-bearing request (spec F-04). */
export const LocationPayload = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  accuracy: z.number().nonnegative(),
  speed: z.number().optional(),
  timestamp: z.iso.datetime({ offset: true }),
  /** App Attest assertion (iOS, base64 CBOR) or Play Integrity token (Android) over locationClientData. */
  assertion: z.string().max(20_000).optional(),
  platform: z.enum(['ios', 'android']).optional(),
  /** iOS App Attest key id the assertion was made with. */
  keyId: z.string().max(100).optional(),
  /** The OS reported this fix as coming from a mock-location provider. */
  mocked: z.boolean().optional(),
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

/**
 * The exact bytes a client signs for a location payload. Fixed-precision formatting keeps Dart and
 * JavaScript in agreement; the version prefix lets the format change later.
 */
export function locationClientData(p: Pick<LocationPayload, 'lat' | 'lng' | 'accuracy' | 'timestamp'>): string {
  return `trace-loc-v1|${p.lat.toFixed(6)}|${p.lng.toFixed(6)}|${p.accuracy.toFixed(1)}|${p.timestamp}`;
}
