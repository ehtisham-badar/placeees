import { describe, expect, it } from 'vitest';
import { evaluateUnlock, unlockRadius, type UnlockInput } from '../src/drops/unlock.js';

const NOW = Date.parse('2026-10-04T14:22:20Z');

function input(overrides: Partial<UnlockInput> = {}, payload: Partial<UnlockInput['payload']> = {}): UnlockInput {
  return {
    payload: { lat: 31.5204, lng: 74.3587, accuracy: 18, timestamp: '2026-10-04T14:22:11Z', ...payload },
    previousFix: null,
    distanceM: 20,
    visible: true,
    unlockAt: null,
    conditionsMet: async () => true,
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
  it('unlocks a nearby, visible drop', async () => {
    expect(await evaluateUnlock(input())).toBeNull();
  });

  it('rejects stale fixes', async () => {
    expect(await evaluateUnlock(input({}, { timestamp: '2026-10-04T14:21:00Z' }))).toBe('stale');
  });

  it('rejects low accuracy', async () => {
    expect(await evaluateUnlock(input({}, { accuracy: 120 }))).toBe('low_accuracy');
  });

  it('rejects impossible travel', async () => {
    const previousFix = { lat: 24.8607, lng: 67.0011, at: new Date('2026-10-04T14:00:00Z') }; // Karachi
    expect(await evaluateUnlock(input({ previousFix }))).toBe('suspicious');
  });

  it('rejects when outside the accuracy-scaled radius', async () => {
    expect(await evaluateUnlock(input({ distanceM: 59 }))).toBe('too_far');
    expect(await evaluateUnlock(input({ distanceM: 57 }))).toBeNull();
  });

  it('rejects invisible drops after the distance check', async () => {
    expect(await evaluateUnlock(input({ visible: false }))).toBe('not_visible');
  });

  it('keeps conditional and capsule drops locked', async () => {
    expect(await evaluateUnlock(input({ conditionsMet: async () => false }))).toBe('condition_locked');
    expect(await evaluateUnlock(input({ unlockAt: new Date(NOW + 60_000) }))).toBe('capsule_locked');
    expect(await evaluateUnlock(input({ unlockAt: new Date(NOW - 60_000) }))).toBeNull();
  });
});

describe('evaluateUnlock ordering', () => {
  it('never evaluates conditions for someone too far away or before a capsule opens', async () => {
    let calls = 0;
    const conditionsMet = async () => {
      calls++;
      return true;
    };
    await evaluateUnlock(input({ distanceM: 500, conditionsMet }));
    await evaluateUnlock(input({ unlockAt: new Date(NOW + 60_000), conditionsMet }));
    expect(calls).toBe(0);
  });
});
