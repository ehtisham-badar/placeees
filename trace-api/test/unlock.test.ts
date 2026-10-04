import { describe, expect, it } from 'vitest';
import { evaluateUnlock, unlockRadius, type UnlockInput } from '../src/drops/unlock.js';

const NOW = Date.parse('2026-10-04T14:22:20Z');

function input(overrides: Partial<UnlockInput> = {}, payload: Partial<UnlockInput['payload']> = {}): UnlockInput {
  return {
    payload: { lat: 31.5204, lng: 74.3587, accuracy: 18, timestamp: '2026-10-04T14:22:11Z', ...payload },
    previousFix: null,
    distanceM: 20,
    visible: true,
    hasConditions: false,
    unlockAt: null,
    now: NOW,
    ...overrides,
  };
}

describe('unlockRadius', () => {
  it('clamps between 40 and 80 m', () => {
    expect(unlockRadius(0)).toBe(40);
    expect(unlockRadius(18)).toBe(58);
    expect(unlockRadius(200)).toBe(80);
  });
});

describe('evaluateUnlock', () => {
  it('unlocks a nearby, visible drop', () => {
    expect(evaluateUnlock(input())).toBeNull();
  });

  it('rejects stale fixes', () => {
    expect(evaluateUnlock(input({}, { timestamp: '2026-10-04T14:21:00Z' }))).toBe('stale');
  });

  it('rejects low accuracy', () => {
    expect(evaluateUnlock(input({}, { accuracy: 120 }))).toBe('low_accuracy');
  });

  it('rejects impossible travel', () => {
    const previousFix = { lat: 24.8607, lng: 67.0011, at: new Date('2026-10-04T14:00:00Z') }; // Karachi
    expect(evaluateUnlock(input({ previousFix }))).toBe('suspicious');
  });

  it('rejects when outside the accuracy-scaled radius', () => {
    expect(evaluateUnlock(input({ distanceM: 59 }))).toBe('too_far');
    expect(evaluateUnlock(input({ distanceM: 57 }))).toBeNull();
  });

  it('rejects invisible drops after the distance check', () => {
    expect(evaluateUnlock(input({ visible: false }))).toBe('not_visible');
  });

  it('keeps conditional and capsule drops locked', () => {
    expect(evaluateUnlock(input({ hasConditions: true }))).toBe('condition_locked');
    expect(evaluateUnlock(input({ unlockAt: new Date(NOW + 60_000) }))).toBe('capsule_locked');
    expect(evaluateUnlock(input({ unlockAt: new Date(NOW - 60_000) }))).toBeNull();
  });
});
