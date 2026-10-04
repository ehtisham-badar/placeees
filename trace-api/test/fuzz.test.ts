import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { FUZZ_MAX_OFFSET_M, FUZZ_MIN_OFFSET_M, FUZZ_RADIUS_M, fuzzyCircle } from '../src/drops/fuzz.js';
import { distanceM } from '../src/lib/geo.js';

const lahore = { lat: 31.5204, lng: 74.3587 };

describe('fuzzyCircle', () => {
  it('is deterministic per drop id', () => {
    const id = randomUUID();
    expect(fuzzyCircle(id, lahore)).toEqual(fuzzyCircle(id, lahore));
  });

  it('offsets 40–120 m and always contains the true point', () => {
    for (let i = 0; i < 500; i++) {
      const { center, radius } = fuzzyCircle(randomUUID(), lahore);
      const d = distanceM(center, lahore);
      expect(d).toBeGreaterThanOrEqual(FUZZ_MIN_OFFSET_M - 0.01);
      expect(d).toBeLessThanOrEqual(FUZZ_MAX_OFFSET_M + 0.01);
      expect(d).toBeLessThan(radius);
      expect(radius).toBe(FUZZ_RADIUS_M);
    }
  });

  it('differs between drops', () => {
    expect(fuzzyCircle(randomUUID(), lahore).center).not.toEqual(fuzzyCircle(randomUUID(), lahore).center);
  });
});
