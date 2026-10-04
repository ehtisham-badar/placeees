import { describe, expect, it } from 'vitest';
import { carryDeadline, dropFailure, MAX_CARRYING, pickupFailure, type PickupInput } from '../src/relays/rules.js';

const ok: PickupInput = {
  isRelay: true,
  isCreator: false,
  carriedBefore: false,
  carrierId: null,
  unlocked: true,
  carryingCount: 0,
};

describe('pickupFailure', () => {
  it('lets someone who opened it carry it on', () => {
    expect(pickupFailure(ok)).toBeNull();
  });

  it('enforces the relay rules', () => {
    expect(pickupFailure({ ...ok, isRelay: false })).toBe('not_a_relay');
    expect(pickupFailure({ ...ok, isCreator: true })).toBe('own_relay');
    expect(pickupFailure({ ...ok, carrierId: 'someone' })).toBe('already_carried');
    expect(pickupFailure({ ...ok, carriedBefore: true })).toBe('carried_before');
    expect(pickupFailure({ ...ok, unlocked: false })).toBe('locked');
    expect(pickupFailure({ ...ok, carryingCount: MAX_CARRYING })).toBe('carrying_limit');
  });
});

describe('dropping a relay', () => {
  it('needs at least 1 km of travel', () => {
    expect(dropFailure(999)).toBe('too_close');
    expect(dropFailure(1000)).toBeNull();
  });

  it('is due 7 days after pickup', () => {
    expect(carryDeadline(new Date('2026-10-05T10:00:00Z')).toISOString()).toBe('2026-10-12T10:00:00.000Z');
  });
});
