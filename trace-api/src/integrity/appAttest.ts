import { createHash, createPublicKey, verify as verifySignature, X509Certificate } from 'node:crypto';
import { decode } from 'cbor-x';
import { APPLE_APP_ATTEST_ROOT_PEM } from './appleRoot.js';

/**
 * iOS App Attest verification (spec F-17), following Apple's "Validating apps that connect to your server".
 * https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server
 */

const appleRoot = new X509Certificate(APPLE_APP_ATTEST_ROOT_PEM);
// DER encoding of OID 1.2.840.113635.100.8.2, the extension carrying the attestation nonce.
const NONCE_OID = Buffer.from('06092a864886f763640802', 'hex');
const AAGUID_DEV = Buffer.from('appattestdevelop');
const AAGUID_PROD = Buffer.concat([Buffer.from('appattest'), Buffer.alloc(7)]);

export const sha256 = (...parts: Buffer[]) => {
  const h = createHash('sha256');
  for (const p of parts) h.update(p);
  return h.digest();
};

export class AttestError extends Error {}

export interface AuthenticatorData {
  rpIdHash: Buffer;
  flags: number;
  counter: number;
  aaguid?: Buffer;
  credentialId?: Buffer;
}

export function parseAuthData(buf: Buffer): AuthenticatorData {
  if (buf.length < 37) throw new AttestError('auth_data_short');
  const data: AuthenticatorData = { rpIdHash: buf.subarray(0, 32), flags: buf[32]!, counter: buf.readUInt32BE(33) };
  if (buf[32]! & 0x40 && buf.length >= 55) {
    data.aaguid = buf.subarray(37, 53);
    const len = buf.readUInt16BE(53);
    data.credentialId = buf.subarray(55, 55 + len);
  }
  return data;
}

interface Tlv {
  tag: number;
  start: number; // first value byte
  end: number; // one past the last value byte
}

function readTlv(buf: Buffer, offset: number): Tlv {
  const tag = buf[offset]!;
  let len = buf[offset + 1]!;
  let start = offset + 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    len = 0;
    for (let i = 0; i < n; i++) len = (len << 8) | buf[start + i]!;
    start += n;
  }
  if (start + len > buf.length) throw new AttestError('der_overflow');
  return { tag, start, end: start + len };
}

/** Pulls the nonce out of the leaf certificate's 1.2.840.113635.100.8.2 extension. */
export function extractNonce(certDer: Buffer): Buffer {
  const oidAt = certDer.indexOf(NONCE_OID);
  if (oidAt < 0) throw new AttestError('nonce_extension_missing');
  let tlv = readTlv(certDer, oidAt + NONCE_OID.length);
  if (tlv.tag === 0x01) tlv = readTlv(certDer, tlv.end); // optional "critical" BOOLEAN
  if (tlv.tag !== 0x04) throw new AttestError('nonce_extension_malformed');
  const seq = readTlv(certDer, tlv.start); // SEQUENCE
  const tagged = readTlv(certDer, seq.start); // [1]
  const octets = readTlv(certDer, tagged.start); // OCTET STRING
  if (seq.tag !== 0x30 || tagged.tag !== 0xa1 || octets.tag !== 0x04) throw new AttestError('nonce_extension_malformed');
  return certDer.subarray(octets.start, octets.end);
}

/** Uncompressed EC point (0x04 || X || Y) of a P-256 public key. */
function rawPoint(cert: X509Certificate): Buffer {
  const jwk = cert.publicKey.export({ format: 'jwk' });
  return Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x!, 'base64url'), Buffer.from(jwk.y!, 'base64url')]);
}

export interface AttestationInput {
  attestation: Buffer;
  /** The one-time challenge the server issued; the client hashes it as clientDataHash. */
  challenge: Buffer;
  keyId: string;
  appId: string; // "<TEAM_ID>.<bundle id>"
  now?: Date;
}

/** Verifies a key attestation. Returns the key to store for later assertions. */
export function verifyAttestation(input: AttestationInput): { publicKeyPem: string; env: 'development' | 'production' } {
  const att = decode(input.attestation) as { fmt?: string; attStmt?: { x5c?: Uint8Array[] }; authData?: Uint8Array };
  if (att.fmt !== 'apple-appattest' || !att.attStmt?.x5c || att.attStmt.x5c.length < 2 || !att.authData) {
    throw new AttestError('bad_format');
  }

  // 1. The certificate chain leads to Apple's App Attestation root.
  const leaf = new X509Certificate(Buffer.from(att.attStmt.x5c[0]!));
  const intermediate = new X509Certificate(Buffer.from(att.attStmt.x5c[1]!));
  const now = input.now ?? new Date();
  for (const c of [leaf, intermediate]) {
    if (now < new Date(c.validFrom) || now > new Date(c.validTo)) throw new AttestError('cert_expired');
  }
  if (!leaf.verify(intermediate.publicKey) || !intermediate.verify(appleRoot.publicKey)) {
    throw new AttestError('bad_chain');
  }

  // 2–4. The nonce in the leaf binds the attestation to our challenge.
  const authData = Buffer.from(att.authData);
  const nonce = sha256(authData, sha256(input.challenge));
  if (!extractNonce(leaf.raw).equals(nonce)) throw new AttestError('nonce_mismatch');

  // 5. The key id is the hash of the attested public key.
  const keyId = Buffer.from(input.keyId, 'base64');
  if (!sha256(rawPoint(leaf)).equals(keyId)) throw new AttestError('key_id_mismatch');

  // 6–9. Authenticator data: our app, a fresh key, the right environment.
  const parsed = parseAuthData(authData);
  if (!parsed.rpIdHash.equals(sha256(Buffer.from(input.appId)))) throw new AttestError('wrong_app');
  if (parsed.counter !== 0) throw new AttestError('counter_not_zero');
  const env = parsed.aaguid?.equals(AAGUID_PROD) ? 'production' : parsed.aaguid?.equals(AAGUID_DEV) ? 'development' : null;
  if (!env) throw new AttestError('bad_aaguid');
  if (!parsed.credentialId?.equals(keyId)) throw new AttestError('credential_mismatch');

  return { publicKeyPem: leaf.publicKey.export({ type: 'spki', format: 'pem' }).toString(), env };
}

export interface AssertionInput {
  assertion: Buffer;
  /** Exactly the bytes the client signed (see locationClientData). */
  clientData: Buffer;
  publicKeyPem: string;
  storedCounter: number;
  appId: string;
}

/** Verifies a per-request assertion. Returns the new counter to store. */
export function verifyAssertion(input: AssertionInput): number {
  const a = decode(input.assertion) as { signature?: Uint8Array; authenticatorData?: Uint8Array };
  if (!a.signature || !a.authenticatorData) throw new AttestError('bad_format');
  const authData = Buffer.from(a.authenticatorData);
  const nonce = sha256(authData, sha256(input.clientData));
  if (!verifySignature('sha256', nonce, createPublicKey(input.publicKeyPem), Buffer.from(a.signature))) {
    throw new AttestError('bad_signature');
  }
  const parsed = parseAuthData(authData);
  if (!parsed.rpIdHash.equals(sha256(Buffer.from(input.appId)))) throw new AttestError('wrong_app');
  // A replayed assertion can't have a higher counter.
  if (parsed.counter <= input.storedCounter) throw new AttestError('replayed');
  return parsed.counter;
}
