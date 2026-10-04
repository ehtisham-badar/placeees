export const MIN_RELAY_HOP_M = 1000;
export const RELAY_CARRY_DAYS = 7;
export const MAX_CARRYING = 3;

export type PickupFailure = 'not_a_relay' | 'own_relay' | 'carried_before' | 'already_carried' | 'locked' | 'carrying_limit';

export interface PickupInput {
  isRelay: boolean;
  isCreator: boolean;
  carriedBefore: boolean;
  carrierId: string | null;
  unlocked: boolean;
  carryingCount: number;
}

/** Who may pick a relay up (spec F-13). Presence is checked separately, like an unlock. */
export function pickupFailure(i: PickupInput): PickupFailure | null {
  if (!i.isRelay) return 'not_a_relay';
  if (i.isCreator) return 'own_relay';
  if (i.carrierId != null) return 'already_carried';
  if (i.carriedBefore) return 'carried_before';
  if (!i.unlocked) return 'locked';
  if (i.carryingCount >= MAX_CARRYING) return 'carrying_limit';
  return null;
}

/** A relay must travel: the new spot has to be at least 1 km from where it was picked up. */
export function dropFailure(distanceFromPickupM: number): 'too_close' | null {
  return distanceFromPickupM < MIN_RELAY_HOP_M ? 'too_close' : null;
}

export function carryDeadline(pickedAt: Date): Date {
  return new Date(pickedAt.getTime() + RELAY_CARRY_DAYS * 86_400_000);
}
