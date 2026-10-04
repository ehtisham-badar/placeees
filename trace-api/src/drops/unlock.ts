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
  unlockAt: Date | null;
  /** Evaluates the drop's conditions (F-08); only called once everything cheaper has passed. */
  conditionsMet: () => Promise<boolean>;
  now?: number;
}

/** Unlock radius grows with reported accuracy: 40 m in open sky, up to 80 m in dense areas. */
export function unlockRadius(accuracy: number): number {
  return Math.min(MAX_UNLOCK_RADIUS_M, Math.max(MIN_UNLOCK_RADIUS_M, 40 + accuracy));
}

/** Server-side unlock validation (spec F-04). Order matters: integrity first, then place, then rules. */
export async function evaluateUnlock(input: UnlockInput): Promise<UnlockFailure | null> {
  const now = input.now ?? Date.now();
  const { payload } = input;

  const freshness = checkFreshness(payload, now);
  if (freshness) return freshness;
  if (payload.accuracy > MAX_UNLOCK_ACCURACY_M) return 'low_accuracy';
  if (isImpossibleTravel(input.previousFix, payload)) return 'suspicious';

  if (input.distanceM > unlockRadius(payload.accuracy)) return 'too_far';
  if (!input.visible) return 'not_visible';
  if (input.unlockAt && now < input.unlockAt.getTime()) return 'capsule_locked';
  if (!(await input.conditionsMet())) return 'condition_locked';
  return null;
}
