import { createHash } from 'node:crypto';
import { config } from '../config.js';
import { sql } from '../db/client.js';
import { AppError } from '../lib/errors.js';
import { AttestError, verifyAssertion } from './appAttest.js';
import { recordIntegrityEvent } from './events.js';
import { locationClientData, type LocationPayload } from './location.js';
import { decodeIntegrityToken, playVerdictProblem } from './playIntegrity.js';

export const appleAppId = () => `${config.APPLE_TEAM_ID}.${config.APPLE_BUNDLE_ID}`;

/**
 * Device + location integrity for every location-bearing request (spec F-17).
 * INTEGRITY_MODE=off skips checks (still logs mock locations), report logs failures, enforce rejects them.
 */
export async function assertTrustedPayload(userId: string, p: LocationPayload): Promise<void> {
  const mode = config.INTEGRITY_MODE;
  const fail = async (kind: Parameters<typeof recordIntegrityEvent>[1], code: string, detail: Record<string, unknown> = {}) => {
    await recordIntegrityEvent(userId, kind, { ...detail, platform: p.platform });
    if (mode === 'enforce') throw new AppError(code, 422);
  };

  if (p.mocked) await fail('mock_location', 'suspicious');
  if (mode === 'off') return;

  if (!p.assertion || !p.platform) return fail('integrity_missing', 'integrity_required');
  const clientData = locationClientData(p);

  if (p.platform === 'ios') {
    if (!p.keyId) return fail('integrity_missing', 'integrity_required');
    const [key] = await sql<{ publicKey: string; counter: string }[]>`
      SELECT public_key, counter FROM attest_keys WHERE key_id = ${p.keyId} AND user_id = ${userId}`;
    if (!key) return fail('attest_failed', 'integrity_failed', { reason: 'unknown_key' });
    try {
      const counter = verifyAssertion({
        assertion: Buffer.from(p.assertion, 'base64'),
        clientData: Buffer.from(clientData),
        publicKeyPem: key.publicKey,
        storedCounter: Number(key.counter),
        appId: appleAppId(),
      });
      // Only move forward, so a concurrent request can't roll the counter back.
      await sql`UPDATE attest_keys SET counter = ${counter} WHERE key_id = ${p.keyId} AND counter < ${counter}`;
    } catch (err) {
      return fail('attest_failed', 'integrity_failed', { reason: err instanceof AttestError ? err.message : 'error' });
    }
    return;
  }

  try {
    const verdict = await decodeIntegrityToken(p.assertion);
    const expected = createHash('sha256').update(clientData).digest('hex');
    const problem = playVerdictProblem(verdict, expected);
    if (problem) return fail('integrity_failed', 'integrity_failed', { reason: problem });
  } catch (err) {
    // Google being unreachable must not lock every Android user out: log it and let the request through.
    await recordIntegrityEvent(userId, 'integrity_failed', { reason: 'decode_error', message: String(err), platform: 'android' });
  }
}
