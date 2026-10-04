import { generateKeyPairSync, sign, X509Certificate } from 'node:crypto';
import { encode } from 'cbor-x';
import { describe, expect, it } from 'vitest';
import { AttestError, extractNonce, parseAuthData, sha256, verifyAssertion } from '../src/integrity/appAttest.js';
import { APPLE_APP_ATTEST_ROOT_PEM } from '../src/integrity/appleRoot.js';
import { locationClientData } from '../src/integrity/location.js';
import { playVerdictProblem, type PlayVerdict } from '../src/integrity/playIntegrity.js';
import { venueLandingHtml } from '../src/venues/routes.js';

const APP_ID = 'ABCDE12345.app.trace.mobile';

function authData(appId: string, counter: number) {
  const buf = Buffer.alloc(37);
  sha256(Buffer.from(appId)).copy(buf, 0);
  buf[32] = 0x01;
  buf.writeUInt32BE(counter, 33);
  return buf;
}

/** Signs like DCAppAttestService.generateAssertion: ECDSA-SHA256 over SHA256(authData || SHA256(clientData)). */
function makeAssertion(privateKey: Parameters<typeof sign>[2], clientData: string, counter: number, appId = APP_ID) {
  const ad = authData(appId, counter);
  const nonce = sha256(ad, sha256(Buffer.from(clientData)));
  return encode({ signature: sign('sha256', nonce, privateKey), authenticatorData: ad });
}

describe('App Attest', () => {
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const publicKeyPem = publicKey.export({ type: 'spki', format: 'pem' }).toString();
  const clientData = locationClientData({ lat: 31.5204, lng: 74.3587, accuracy: 18.4, timestamp: '2026-10-04T14:22:11Z' });

  it('ships the genuine Apple root (self-signature verifies)', () => {
    const root = new X509Certificate(APPLE_APP_ATTEST_ROOT_PEM);
    expect(root.subject).toContain('Apple App Attestation Root CA');
    expect(root.verify(root.publicKey)).toBe(true);
  });

  it('accepts a valid assertion and returns the new counter', () => {
    const assertion = makeAssertion(privateKey, clientData, 5);
    expect(verifyAssertion({ assertion, clientData: Buffer.from(clientData), publicKeyPem, storedCounter: 4, appId: APP_ID })).toBe(5);
  });

  it('rejects replays, other apps, tampered payloads and other keys', () => {
    const base = { clientData: Buffer.from(clientData), publicKeyPem, appId: APP_ID };
    expect(() => verifyAssertion({ ...base, assertion: makeAssertion(privateKey, clientData, 5), storedCounter: 5 })).toThrow('replayed');
    expect(() =>
      verifyAssertion({ ...base, assertion: makeAssertion(privateKey, clientData, 6, 'OTHER.app'), storedCounter: 0 }),
    ).toThrow('wrong_app');
    expect(() =>
      verifyAssertion({ ...base, clientData: Buffer.from(clientData + 'x'), assertion: makeAssertion(privateKey, clientData, 6), storedCounter: 0 }),
    ).toThrow('bad_signature');
    const other = generateKeyPairSync('ec', { namedCurve: 'P-256' });
    expect(() => verifyAssertion({ ...base, assertion: makeAssertion(other.privateKey, clientData, 6), storedCounter: 0 })).toThrow(AttestError);
  });

  it('parses authenticator data with attested credential', () => {
    const cred = Buffer.alloc(32, 7);
    const buf = Buffer.concat([authData(APP_ID, 0), Buffer.from('appattestdevelop'), Buffer.from([0, 32]), cred]);
    buf[32] = 0x41;
    const parsed = parseAuthData(buf);
    expect(parsed.counter).toBe(0);
    expect(parsed.aaguid?.toString()).toBe('appattestdevelop');
    expect(parsed.credentialId?.equals(cred)).toBe(true);
  });

  it('finds the nonce inside the 1.2.840.113635.100.8.2 extension', () => {
    const nonce = Buffer.alloc(32, 0xab);
    // OID, then OCTET STRING { SEQUENCE { [1] { OCTET STRING nonce } } }, surrounded by other bytes.
    const ext = Buffer.concat([
      Buffer.from('06092a864886f763640802', 'hex'),
      Buffer.from([0x04, 0x24, 0x30, 0x22, 0xa1, 0x20, 0x04, 0x20]),
      nonce,
    ]);
    const cert = Buffer.concat([Buffer.from([0x30, 0x82, 0x01, 0x00, 0x04, 0x20]), Buffer.alloc(32), ext, Buffer.alloc(8)]);
    expect(extractNonce(cert).equals(nonce)).toBe(true);
    expect(() => extractNonce(Buffer.alloc(64))).toThrow('nonce_extension_missing');
  });
});

describe('location client data', () => {
  it('is fixed-precision so Dart and JavaScript agree', () => {
    expect(locationClientData({ lat: 31.52, lng: 74.3587123, accuracy: 18, timestamp: '2026-10-04T14:22:11Z' })).toBe(
      'trace-loc-v1|31.520000|74.358712|18.0|2026-10-04T14:22:11Z',
    );
  });
});

describe('Play Integrity verdicts', () => {
  const now = Date.parse('2026-10-05T10:00:00Z');
  const good: PlayVerdict = {
    requestDetails: { requestPackageName: 'app.trace.mobile', requestHash: 'abc', timestampMillis: String(now - 5_000) },
    appIntegrity: { appRecognitionVerdict: 'PLAY_RECOGNIZED' },
    deviceIntegrity: { deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY'] },
  };

  it('accepts a genuine, fresh verdict for this request', () => {
    expect(playVerdictProblem(good, 'abc', now)).toBeNull();
  });

  it('rejects anything off', () => {
    expect(playVerdictProblem(good, 'other', now)).toBe('hash_mismatch');
    expect(playVerdictProblem({ ...good, requestDetails: { ...good.requestDetails, requestPackageName: 'evil' } }, 'abc', now)).toBe('wrong_package');
    expect(playVerdictProblem(good, 'abc', now + 120_000)).toBe('stale_token');
    expect(playVerdictProblem({ ...good, appIntegrity: { appRecognitionVerdict: 'UNRECOGNIZED_VERSION' } }, 'abc', now)).toBe('unrecognized_app');
    expect(playVerdictProblem({ ...good, deviceIntegrity: { deviceRecognitionVerdict: [] } }, 'abc', now)).toBe('device_integrity');
  });
});

describe('venue landing page', () => {
  it('escapes venue content', () => {
    const html = venueLandingHtml({ code: 'H7K2M9QX', name: '<script>x</script>', teaser: '"hi" & bye' });
    expect(html).not.toContain('<script>x</script>');
    expect(html).toContain('&lt;script&gt;');
    expect(html).toContain('&quot;hi&quot; &amp; bye');
    expect(html).toContain('trace://v/H7K2M9QX');
  });
});
