import { describe, expect, it } from 'vitest';
import { isImpossibleTravel } from '../src/integrity/location.js';
import { destination, distanceM, geohash } from '../src/lib/geo.js';

describe('geo', () => {
  it('computes geohash-7', () => {
    expect(geohash({ lat: 57.64911, lng: 10.40744 }, 7)).toBe('u4pruyd');
  });

  it('destination and distance agree', () => {
    const from = { lat: 31.5, lng: 74.3 };
    expect(distanceM(from, destination(from, 73, 1234))).toBeCloseTo(1234, 3);
  });
});

describe('isImpossibleTravel', () => {
  const at = new Date('2026-10-04T14:00:00Z');
  const base = { lat: 31.5204, lng: 74.3587, accuracy: 10 };

  it('ignores small hops', () => {
    const p = { ...base, lat: 31.525, timestamp: '2026-10-04T14:00:01Z' };
    expect(isImpossibleTravel({ lat: 31.5204, lng: 74.3587, at }, p)).toBe(false);
  });

  it('allows a car journey', () => {
    const p = { ...base, lat: 31.6, timestamp: '2026-10-04T14:10:00Z' }; // ~9 km in 10 min
    expect(isImpossibleTravel({ lat: 31.5204, lng: 74.3587, at }, p)).toBe(false);
  });

  it('flags teleporting', () => {
    const p = { ...base, lat: 32.5, timestamp: '2026-10-04T14:05:00Z' }; // ~110 km in 5 min
    expect(isImpossibleTravel({ lat: 31.5204, lng: 74.3587, at }, p)).toBe(true);
  });
});
