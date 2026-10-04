import { config } from '../config.js';
import { googleAccessToken } from '../lib/googleAuth.js';

/** The parts of a decoded Play Integrity verdict we rely on. */
export interface PlayVerdict {
  requestDetails?: { requestPackageName?: string; requestHash?: string; timestampMillis?: string };
  appIntegrity?: { appRecognitionVerdict?: string };
  deviceIntegrity?: { deviceRecognitionVerdict?: string[] };
}

export const MAX_TOKEN_AGE_MS = 60_000;

/** Why a verdict should not be trusted, or null if it's fine (spec F-17). */
export function playVerdictProblem(v: PlayVerdict, expectedHash: string, now = Date.now()): string | null {
  const req = v.requestDetails;
  if (req?.requestPackageName !== config.ANDROID_PACKAGE) return 'wrong_package';
  if (req.requestHash !== expectedHash) return 'hash_mismatch';
  if (!req.timestampMillis || now - Number(req.timestampMillis) > MAX_TOKEN_AGE_MS) return 'stale_token';
  if (v.appIntegrity?.appRecognitionVerdict !== 'PLAY_RECOGNIZED') return 'unrecognized_app';
  if (!v.deviceIntegrity?.deviceRecognitionVerdict?.includes('MEETS_DEVICE_INTEGRITY')) return 'device_integrity';
  return null;
}

function serviceAccount() {
  const clientEmail = config.GOOGLE_SA_CLIENT_EMAIL || config.FCM_CLIENT_EMAIL;
  const privateKey = config.GOOGLE_SA_PRIVATE_KEY || config.FCM_PRIVATE_KEY;
  if (!clientEmail || !privateKey) throw new Error('play integrity not configured');
  return { clientEmail, privateKey };
}

/** Asks Google to decrypt and verify an integrity token. */
export async function decodeIntegrityToken(token: string): Promise<PlayVerdict> {
  const access = await googleAccessToken(serviceAccount(), 'https://www.googleapis.com/auth/playintegrity');
  const res = await fetch(`https://playintegrity.googleapis.com/v1/${config.ANDROID_PACKAGE}:decodeIntegrityToken`, {
    method: 'POST',
    headers: { authorization: `Bearer ${access}`, 'content-type': 'application/json' },
    body: JSON.stringify({ integrity_token: token }),
    signal: AbortSignal.timeout(5000),
  });
  if (!res.ok) throw new Error(`play integrity ${res.status}`);
  return ((await res.json()) as { tokenPayloadExternal: PlayVerdict }).tokenPayloadExternal;
}
