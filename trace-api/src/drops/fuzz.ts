import { createHash } from 'node:crypto';
import { destination, type LatLng } from '../lib/geo.js';

export const FUZZ_MIN_OFFSET_M = 40;
export const FUZZ_MAX_OFFSET_M = 120;
export const FUZZ_RADIUS_M = 150;

/**
 * Deterministic fuzzy marker for a drop (spec F-03). The offset is derived from the drop id,
 * so the circle never jumps between refreshes, and the true point always lies inside it.
 */
export function fuzzyCircle(dropId: string, truePoint: LatLng) {
  const digest = createHash('sha256').update(`trace-fuzz:${dropId}`).digest();
  const u1 = digest.readUInt32BE(0) / 0xffffffff;
  const u2 = digest.readUInt32BE(4) / 0xffffffff;
  const offset = FUZZ_MIN_OFFSET_M + u1 * (FUZZ_MAX_OFFSET_M - FUZZ_MIN_OFFSET_M);
  const center = destination(truePoint, u2 * 360, offset);
  return { center, radius: FUZZ_RADIUS_M };
}
