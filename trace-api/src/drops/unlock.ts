import { checkFreshness, isImpossibleTravel, type LocationPayload, type PreviousFix } from '../integrity/location.js';

export const MAX_UNLOCK_ACCURACY_M = 80;
export const MIN_UNLOCK_RADIUS_M = 40;
export const MAX_UNLOCK_RADIUS_M = 80;

export type UnlockFailure =
  | 'stale'
  | 'low_accuracy'
  | 'suspicious'
  | 'too_far'
  | 'not_visible'
  | 'condition_locked'
  | 'capsule_locked';

export interface UnlockInput {
  payload: LocationPayload;
  previousFix: PreviousFix | null;
  /** Distance from the payload to the drop's true point, computed by PostGIS. */
  distanceM: number;
  visible: boolean;
  hasConditions: boolean;
  unlockAt: Date | null;
  now?: number;
}

/** Unlock radius grows with reported accuracy: 40 m in open sky, up to 80 m in dense areas. */
export function unlockRadius(accuracy: number): number {
  return Math.min(MAX_UNLOCK_RADIUS_M, Math.max(MIN_UNLOCK_RADIUS_M, 40 + accuracy));
}

/** Server-side unlock validation (spec F-04). Order matters: integrity first, then place, then rules. */
export function evaluateUnlock(input: UnlockInput): UnlockFailure | null {
  const now = input.now ?? Date.now();
  const { payload } = input;

  const freshness = checkFreshness(payload, now);
  if (freshness) return freshness;
  if (payload.accuracy > MAX_UNLOCK_ACCURACY_M) return 'low_accuracy';
  if (isImpossibleTravel(input.previousFix, payload)) return 'suspicious';

  if (input.distanceM > unlockRadius(payload.accuracy)) return 'too_far';
  if (!input.visible) return 'not_visible';
  // Conditional drops (F-08) are evaluated in phase 2; until then they stay locked.
  if (input.hasConditions) return 'condition_locked';
  if (input.unlockAt && now < input.unlockAt.getTime()) return 'capsule_locked';
  return null;
}
